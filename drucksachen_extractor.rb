#!/usr/bin/env ruby
# encoding: UTF-8

require 'rubygems'
require 'nokogiri'


def parseDrucksachen(htmlString)
  doc = Nokogiri::HTML(htmlString)

  drucksachen = []

  next_drucksache = {
    type: "",
    number: "",
    title: "",
    link: ""
  }

  doc.css("tr").each_with_index do |row,i|
    next if i < 2
    tds = row.css("td")
    if tds.count == 1
      next_drucksache[:type] = tds.first.css("p")[0].text.strip
    elsif tds.count == 3
      next_drucksache[:number] = tds[1].css("p")[0].inner_html.gsub(/<br>/, ' ').strip
      next_drucksache[:title] = tds[2].css("p a")[0].text.strip
      next_drucksache[:link] = tds[2].css("p a")[0].attr('href').strip
      drucksachen << next_drucksache.clone
    end
  end

  return drucksachen

end
