# encoding: utf-8

require 'bundler/setup'
require 'csv'
require 'anemone'
require 'nokogiri'
require 'mail'
require 'yaml'
require 'kconv'

class OutputData
  def initialize(result)
    @mail_config = YAML.load_file('mail.yml')
    @csv_data    = result[:csv_data]
    @log         = result[:log]
    @error_flag  = result[:error_flag]
    @num_name    = result[:num_name]
  end

  def push_csv
    begin
      # エラーログがない場合, scraping_website.csvに出力
      # ファイルが存在しない場合, 新規作成時処理
      file_flag = File.exist?("scraping_website.csv") ? true : false
      if @error_flag == false
        CSV.open("scraping_website.csv","a") do |csv|
          csv << @num_name unless file_flag
          csv << @csv_data
        end
      end
    rescue => e
      puts "CSV書き込みができませんでした."
      puts e.message
    end
  end

  def mail
    begin
      mail = Mail.new
      options = {
        :address              => "smtp.gmail.com",
        :port                 => 587,
        :domain               => "smtp.gmail.com",
        :user_name            => @mail_config['gmail']['username'],
        :password             => @mail_config['gmail']['password'],
        :authentication       => :plain,
        :enable_starttls_auto => true
      }
      mail.charset = 'utf-8'
      mail.attachments["scraping_website.csv"] = File.binread("scraping_website.csv")
      mail.attachments["target.txt"] = File.binread("target.yml")
      mail.from @mail_config['mail']['from_address']
      mail.to @mail_config['mail']['to_address']
      mail.subject '競合他社の数値自動化スクリプト結果です!'
      mail.body @log
      mail.delivery_method(:smtp, options)
      mail.deliver
    rescue => e
      puts "メールが送信できません.\n"
      puts e.message
    end
  end
end

class Scraping
  attr_accessor :url, :site_name, :pathes, :remove_string, :user_agent, :delay

  def initialize()
    @url           = nil
    @site_name     = nil
    @pathes        = nil
    @remove_string = nil
    @user_agent    = nil
    @delay         = nil
  end

  def output_website
    if @site_name != 'nil'
      puts '------------------------------------------'
      puts "#{@site_name}"
      puts '------------------------------------------'
    end
  end

  def self.output_value(key, value)
    puts key + ' = ' + value
    return key.tosjis
  end

  def crawl
    opts = {
      user_agent: @user_agent.to_s,
      delay: @delay.to_i
    }
    result, log, key, hash = [], [], [], {}
    error_flag = false
    Anemone.crawl(@url, opts) do |anemone|
      anemone.on_every_page do |page|
        begin
          @pathes.values.each_with_index do |path, i|
            data = page.doc.xpath("#{path}")[0].to_s
            data.strip! if data.strip! != 'nil'
            data = /#{@remove_string}/.match(data).pre_match if @remove_string != 'nil'
              key << Scraping.output_value(@pathes.keys[i], data)
            result << data
          end
          hash = { result: result, log: log, error_flag: error_flag, site_name: @site_name, num_name: key }
          return hash
        rescue => e
          puts e.message
          log << e.message + "\n"
          error_flag = true
          hash = { result: result, log: log, error_flag: error_flag, site_name: @site_name, num_name: key }
          return hash
        end
      end
    end
  end

  def self.format(crawl_result)
    csv_data, log, num_name, result_hash = [], [], [], {}
    error_flag = false
    date = Time.now.strftime("%y-%m-%d(#{%w(日 月 火 水 木 金 土)[Time.now.wday]})")
    crawl_result.each do |r|
      csv_data << r[:result]
      log << r[:log]
      error_flag = r[:error_flag]
      num_name << r[:num_name]
    end
    num_name.unshift(" ")
    csv_data.unshift(date.tosjis)
    result_hash = {
      csv_data: csv_data.flatten,
      log: log,
      error_flag: error_flag,
      num_name: num_name.flatten
    }
    return result_hash
  end
end

crawl_result = []
targets = YAML.load_file('target.yml')

scraping = Scraping.new()
targets['target_list'].each do |list|
  scraping.url           = list['url']
  scraping.site_name     = list['site_name']
  scraping.pathes        = list['path']
  scraping.remove_string = list['remove_string']
  scraping.user_agent    = list['user_agent']
  scraping.delay         = list['delay']
  scraping.output_website
  crawl_result << scraping.crawl
end
result = Scraping.format(crawl_result)
output_data = OutputData.new(result)
output_data.push_csv
output_data.mail
