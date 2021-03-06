jQuery.timeago.settings.strings =
  prefixAgo: "vor",
  prefixFromNow: "in",
  suffixAgo: "",
  suffixFromNow: "",
  seconds: "wenigen Sekunden",
  minute: "etwa einer Minute",
  minutes: "%d Minuten",
  hour: "etwa einer Stunde",
  hours: "%d Stunden",
  day: "etwa einem Tag",
  days: "%d Tagen",
  month: "etwa einem Monat",
  months: "%d Monaten",
  year: "etwa einem Jahr",
  years: "%d Jahren"

$ ->
  refresh_date = ->
    $(".date").each ->
      me = $(@)
      date = new Date(1000 * me.data("time"))
      me.html $.timeago(date)

    setTimeout refresh_date, 50000

  refresh_date()
  window.refresh_date = refresh_date

