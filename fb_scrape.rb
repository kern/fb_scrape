#!/usr/bin/env ruby

require 'csv'
require 'json'
require 'net/http'
require 'thread'

if ENV['ACCESS_TOKEN'].nil?
  puts "You must specify a Facebook Graph API access token in ACCESS_TOKEN."
  exit 1
end

class ThreadPool

  DEFAULT_POOL_SIZE = 100
  
  def initialize(size = DEFAULT_POOL_SIZE)
    @queue = Queue.new
    @threads = (0...size).map do
      Thread.new do
        catch :exit do
          loop do
            block, args = @queue.pop
            block.call(*args)
          end
        end
      end
    end
  end

  def schedule(*args, &block)
    @queue << [block, args]
  end

  def join
    @threads.size.times do
      schedule { throw :exit }
    end

    @threads.each(&:join)
  end

end

class FBScrapeCLI

  COMMANDS = [:post_ids, :fetch, :help]
  IDS_LIMIT = 1000
  RETRY_TIME = 5 * 60
  FIELDS = ['id', 'from', 'to', 'message', 'created_time', 'updated_time', 'type', 'picture', 'link', 'source', 'name', 'caption', 'description', 'comments.limit(10000)%7Bid,from,message,created_time,likes.limit(10000)%7D', 'likes.limit(10000)']
  COLUMNS = [
    :id,
    :from_id,
    :from_name,
    :group_id,
    :group_name,
    :message,
    :created_time,
    :updated_time,
    :type,
    :picture,
    :link,
    :source,
    :name,
    :caption,
    :description,
    :like_count,
    :comment_count,
    :parent_id,
    :parent_type,
    :comment_index
  ]

  def initialize(argv, access_token)
    @command = COMMANDS.include?(argv[0].to_sym) ? argv[0].to_sym : :help
    @args = argv[1..-1] || []
    @access_token = access_token
  end

  def run
    send(@command)
  rescue => ex
    STDERR.puts "Error: #{ex.message}"
    STDERR.puts ex.backtrace.map { |s| "  #{s}" }.join("\n")
    exit 1
  end

  def post_ids
    if @args.length != 1
      puts "[usage] fb_scrape post_ids GROUP_ID"
      exit 1
    end

    group_id = @args[0]
    uri = URI("https://graph.facebook.com/v2.3/#{group_id}/feed?access_token=#{@access_token}&fields=id&limit=#{IDS_LIMIT}")

    catch :end do
      graph_connection do |conn|
        loop do

          req = Net::HTTP::Get.new(uri)
          res = conn.request(req)
          json = JSON.parse(res.body)

          if res.kind_of?(Net::HTTPSuccess)
            json['data'].each do |post|
              puts post['id']
            end

            throw :end unless json['paging'] && json['paging']['next']
            uri = URI(json['paging']['next'])
          else
            raise "#{json['error']['type']} - #{json['error']['message']}"
          end

        end
      end
    end
  end

  def fetch
    CSV(STDOUT) do |csv|

      csv << COLUMNS
      pool = ThreadPool.new

      while line = STDIN.gets
        id = line.chomp
        pool.schedule(id) do |id|
          begin
            fetch_post(id).each do |row|
              csv << row
            end
          rescue => ex
            STDERR.puts "Error while fetching #{id}: #{ex.message}. Retrying in 5 minutes..."
            sleep RETRY_TIME
            retry
          end
        end
      end

      pool.join

    end
  end

  def help
    puts "[usage] fb_scrape COMMAND [*ARGS]"
    puts "Supported commands: #{COMMANDS.join(' ')}"
  end

  private

  def fetch_post(id)
    graph_connection do |conn|

      uri = URI("https://graph.facebook.com/v2.3/#{id}?access_token=#{@access_token}&fields=#{FIELDS.join(',')}")
      req = Net::HTTP::Get.new(uri)
      res = conn.request(req)
      json = JSON.parse(res.body)

      if res.kind_of?(Net::HTTPSuccess)

        likes = json['likes'] ? json['likes']['data'] : []
        comments = json['comments'] ? json['comments']['data'] : []

        group_id = json['to']['data'][0]['id']
        group_name = json['to']['data'][0]['name']

        rows = [{
          id: json['id'],
          from_id: json['from'] ? json['from']['id'] : nil,
          from_name: json['from'] ? json['from']['name'] : nil,
          group_id: group_id,
          group_name: group_name,
          message: json['message'],
          created_time: json['created_time'],
          updated_time: json['updated_time'],
          type: json['type'],
          picture: json['picture'],
          link: json['link'],
          source: json['source'],
          name: json['name'],
          caption: json['caption'],
          description: json['description'],
          like_count: likes.size,
          parent_id: group_id,
          parent_type: 'group',
          comment_count: comments.size
        }]

        likes.each do |like|
          rows << {
            from_id: like['id'],
            from_name: like['name'],
            group_id: group_id,
            group_name: group_name,
            parent_id: json['id'],
            parent_type: json['type'],
            type: 'like'
          }
        end

        comments.each_with_index do |comment, index|

          likes = comment['likes'] ? comment['likes']['data'] : []

          rows << {
            id: comment['id'],
            from_id: comment['from'] ? comment['from']['id'] : nil,
            from_name: comment['from'] ? comment['from']['name'] : nil,
            group_id: group_id,
            group_name: group_name,
            message: comment['message'],
            created_time: comment['created_time'],
            type: 'comment',
            like_count: likes.size,
            parent_id: json['id'],
            parent_type: json['type'],
            comment_index: index
          }

          likes.each do |like|
            rows << {
              from_id: like['id'],
              from_name: like['name'],
              group_id: group_id,
              group_name: group_name,
              parent_id: comment['id'],
              parent_type: 'comment',
              type: 'like'
            }
          end

        end

        rows.map { |r| hash_to_row(r) }

      else
        raise "#{json['error']['type']} - #{json['error']['message']}"
      end
    end
  end

  def hash_to_row(hash)
    COLUMNS.map { |col| hash[col] }
  end

  def graph_connection
    Net::HTTP.start('graph.facebook.com', 443, use_ssl: true) do |conn|
      yield conn
    end
  end

end

cli = FBScrapeCLI.new(ARGV, ENV['ACCESS_TOKEN'])
cli.run
