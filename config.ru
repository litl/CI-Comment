require 'rubygems'
require 'sinatra'
require './comment.rb'

# http://www.sinatrarb.com/configuration.html
set :environment, :production
disable :logging, :static, :run, :dump_errors, :show_exceptions

run Comment