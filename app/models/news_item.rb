require "fetcher"
class NewsItem < ActiveRecord::Base
  is_impressionable counter_cache: true, column_name: :impression_count, unique: [:impressionable_type, :impressionable_id, :session_hash]

  def self.max_age
    Setting.max_age.to_i.days
  end

  scope :visible, -> { where('blacklisted != ?', true).where('value is not null and value > 0').where(source_id: Source.visible.select('id')) }
  scope :show_page, -> { where('blacklisted != ?', true).
                         order('published_at desc').
                         where('absolute_score is not null and absolute_score > 0') }
  scope :newspaper, -> { where('blacklisted != ?', true).where('absolute_score is not null and absolute_score >= 0').order('absolute_score desc') }
  scope :current, -> { visible.recent }
  scope :old, -> { where("published_at < ?", (max_age + 1.day).ago) }
  scope :home_page, -> { where('value > 0').visible.order("value desc").where("value is not null").current }
  scope :sorted, -> { visible.order("value desc") }
  scope :recent, -> { where("published_at > ?", max_age.ago) }
  scope :top_of_day, ->(date) { newspaper.where('date(published_at) = ?', date.to_date) }

  scope :uncategorized, lambda {
    joins('LEFT JOIN "categories_news_items" ON "categories_news_items"."news_item_id" = "news_items"."id"').
      where('news_item_id is null').
      group('news_items.id')
  }

  belongs_to :source
  has_and_belongs_to_many :categories
  has_many :incoming_links, class_name: "Linkage", foreign_key: "to_id"
  has_many :outgoing_links, class_name: "Linkage", foreign_key: "from_id", source: :from
  has_many :referenced_news, -> { where('different = ?', true) }, class_name: "NewsItem", through: :incoming_links, source: 'from'
  has_many :referencing_news, -> { where('different = ?', true) }, class_name: "NewsItem", through: :outgoing_links, source: 'to'

  before_save :categorize
  before_save :filter_plaintext
  before_save :blacklist

  validates_uniqueness_of :guid, scope: [:source_id]

  NEWSLETTER_SIZE = [140, 70]
  has_attached_file :image,
    styles: {
      original: ["250x200>", :jpg],
      newsletter: [NEWSLETTER_SIZE.join('x')+"^", :jpg] },
    processors: [:thumbnail, :paperclip_optimizer],
    convert_options: {
      newsletter: "-flatten -colorspace RGB -size #{NEWSLETTER_SIZE.join("x")} xc:white +swap -gravity center -composite"
    }
  do_not_validate_attachment_file_type :image

  include PgSearch
  pg_search_scope :search_full_text,
                  order_within_rank: "news_items.published_at DESC",
                  against: :search_vector,
                  using: {
                    tsearch: {
                      dictionary: 'german',
                      any_word: true,
                      prefix: true,
                      tsvector_column: 'search_vector'
                    }
                  }

  def self.cronjob
    Rails.logger.info "Starting NewsItem refresh cronjob"
    priority = NewsItem.recent.where(value: nil)
    priority.each(&:refresh)
    NewsItem.recent.shuffle.each do |ni|
      next if priority.include?(ni)
      ni.refresh
    end
    Rails.logger.info "Finished NewsItem refresh cronjob"
  end

  # freshness max 120
  def to_data
    {
      facebook: fb_likes,
      twitter: retweets,
      linkedin: linkedin,
      xing: xing,
      gplus: gplus,
      reddit: reddit || 0,
      freshness:  (published_at.to_i - self.class.max_age.ago.to_i) / 10_000,
      bias: source.value,
      impression_count: impression_count,
      multiplicator: source.multiplicator,
      word_length: word_length,
      categories: category_ids,
      # parallel_news_count: source.news_items.where('published_at between ? and ?', 1.week.ago, 1.week.from_now).count,
      published_at: published_at.to_i,
      incoming_link_count: incoming_link_count || 0
    }
  end

  def categorize
    if plaintext
      Categorizer.run(self)
    end
  end

  def filter_plaintext
    self.plaintext = ActionController::Base.helpers.strip_tags(full_text || teaser || title || "")
    self.word_length = words.length
    self.incoming_link_count = referenced_news.count
  end

  def words
    plaintext.split(/[^\p{Word}]+/)
  end

  def get_full_text
    NewsItem::FullTextFetcher.new(self).run
  end

  def refresh
    if source.should_fetch_stats?(self)
      NewsItem::LikeFetcher.fetch_for_news_item(self)
    end
    rescore!
  end

  def rescore!
    result = NewsItem::ScoringAlgorithm.new(to_data, max_age: self.class.max_age.ago).run
    self.absolute_score = result[:absolute_score]
    self.value = result[:relative_score]
    save
  end

  def to_partial_path
    "news_items/#{source.class.model_name.element}_item"
  end

  def social_url
    if source.is_a?(RedditSource)
      source.url + "/comments/#{guid}/"
    end
  end

  def blacklist
    bl = ['Morgenimpuls', 'commun.it', '(insight by', 'Partner im Profil:', 'Partner kurz vorgestellt', 'Partner im Fokus', 'Partner im Blickpunkt',
          'Förderer kurz vorgestellt', 'Förderer im Fokus', 'Förderer im Blickpunkt', 'Community-Partner', 'Community-Förderer']
    if title and bl.any? { |t| title.include?(t) }
      self.blacklisted = true
    end
  end

  def as_json(options)
    super(methods: :image_url_full)
  end

  def image_url_full
    "http://www.hrfilter.de" + image.url
  end

end
