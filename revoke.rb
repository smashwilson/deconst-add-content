#!/bin/env ruby

require 'httparty'

ARGV.each do |key|
  HTTParty.delete "https://developer.rackspace.com:9000/keys/#{key}",
    headers: { "Authorization" => "deconst apikey=\"#{ENV['ADMIN_APIKEY']}\"" }
  puts "Key [#{key}] revoked."
end
