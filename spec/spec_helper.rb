require 'rake'
require 'rspec'
require 'hatchet'
require 'sequel'

require "#{Rake.application.original_dir}/lib/entity_store_sequel"

require_relative '../lib/sequel/core_ext'

include EntityStore
include EntityStoreSequel

Hatchet.configure do |config|
  config.level :fatal
  config.formatter = Hatchet::SimpleFormatter.new
  config.appenders << Hatchet::LoggerAppender.new do |appender|
    appender.logger = Logger.new(STDOUT)
  end
end
include Hatchet

EntityStore::Config.logger = log

def random_string
  (0...24).map{ ('a'..'z').to_a[rand(26)] }.join
end

def random_integer
  rand(9999)
end

def random_time
  Time.at(Time.now.to_i - random_integer)
end

def random_object_id
  BSON::ObjectId.from_time(random_time, :unique => true).to_s
end
