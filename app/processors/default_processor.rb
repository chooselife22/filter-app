class DefaultProcessor < Processor
  def process(source)
    @source = source
    feed = Feedjira::Feed.fetch_and_parse(source.url, max_redirects: 5, timeout: 30)
    if !feed.respond_to?(:entries)
      source.update_column :has_error, true
      # TODO Error reporting
    else
      source.update_column :has_error, false
      feed.entries.each do |entry|
        process_entry(entry)
      end
    end
  end

  def news_item_by_guid(guid)
    guid = guid[0..230]
    old = @source.news_items.where(guid: guid).first
    old || NewsItem.new( guid: guid)
  end

  def process_entry(entry)
    @entry = entry
    title = entry.title
    url = entry.url
    text = entry.content || entry.summary
    published = entry.published
    guid = (entry.entry_id || entry.url)
    return if published < FetcherConcern::MAX_AGE.days.ago
    @item = news_item_by_guid(guid)
    @item.url ||= url
    if @item.new_record?
      @item.source = @source
      @item.published_at = published
    end
    categories(@item)
    follow_url(@item)
    @item.assign_attributes(
      teaser: teaser(text),
      title: title,
    )
    @item.save!
  end

  def follow_url(item)
    if @source.full_text_selector?
      if item.full_text.blank?
        page = get(item.url)
        item.url = page.uri.to_s.gsub(/\?utm_source.*/,"")
        content = page.at(@source.full_text_selector)
        content.search('script, .dd_post_share, .dd_button_v, .dd_button_extra_v, #respond').remove
        item.full_text = clear content.inner_html
      end
    else
      @item.full_text = @entry.content || @entry.summary
    end
  end

  def categories(item)
    @entry.categories
  end

end