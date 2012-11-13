=begin
 Copyright 2012 litl, LLC.
 
 litl, LLC. licenses Comment CI to you under the
 Apache License, Version 2.0 (the "License");
 you may not use this file except in compliance
 with the License.  You may obtain a copy of
 the License at
 
 http://www.apache.org/licenses/LICENSE-2.0
 
 Unless required by applicable law or agreed to in writing,
 software distributed under the License is distributed on an
 "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
 KIND, either express or implied.  See the License for the
 specific language governing permissions and limitations
 under the License.
=end
require 'rubygems'
require 'sqlite3'
require 'faraday'
require 'typhoeus'
require 'typhoeus/adapters/faraday'
require 'multi_json'

MultiJson.use :oj

@@debug = false

if @@debug
  require 'pry'
  require 'awesome_print'
end

# public/ folder must exist for passenger
class Comment < Sinatra::Base

  @@db = SQLite3::Database.new 'comment.db'

  # pull : pull request number.
  # id   : unique comment id
  @@db.execute %(
    create table if not exists comment (
      pull int,
      id int
    );
  )

  def add pull_request_number, comment_id
    @@db.execute "insert into comment values(#{pull_request_number},#{comment_id});"
  end
  
  def remove repo, pull_request_number
    # Get all comments on the pull request
    @@db.execute "select id from comment where pull == #{pull_request_number}" do | row |
      comment_id = row.first
      remove_comment repo, comment_id
    end
  end
  
  # Remove comment from GitHub and then
  # remove from database if successful.
  # comment_id is unique identifier within repo scope.
  # http://developer.github.com/v3/issues/comments/
  def remove_comment repo, comment_id
    response = @@connection.delete do | request |
      request.url "repos/#{repo}/issues/comments/#{comment_id}"
      request.headers['Authorization'] = "token #{@@token}"
    end
    
    # look for Status: 204 No Content
    return if response.env[:status] != 204
 
    # Comment successfully deleted from GitHub so remove from comment.db
    @@db.execute "delete from comment where id == #{comment_id}"
  end
 
  # must be @@global or it's not in scope for Sinatra.
  # Read token from first line of key.txt
  @@token = File.open('key.txt').first
  @@secret = File.open('secret.txt').first

  @@connection = Faraday.new(:url => 'https://api.github.com/') do | faraday |
    faraday.request :url_encoded
    faraday.response :logger if @@debug # log to STDOUT on debug
    faraday.adapter :typhoeus
  end

  # Returns head of pull request. Head represents the last SHA1 of the pull request.
  # nil is returned on failure.
  #
  # repo  - the repo name.    Example: owner/repo
  # issue - the issue number. Example: 3
  def get_last_sha repo, issue
    response = @@connection.get do | request |
      request.url "repos/#{repo}/pulls/#{issue}"
      request.headers['Authorization'] = "token #{@@token}"
    end

    return nil if response.env[:status] != 200

    body = MultiJson.load(response.env[:body])
    return body['head']['sha']
  end

  # secret  : the password known only to comment.rb.
  #           must match or app halts with 404.
  # comment : the text of the comment to post on github.
  #           may include emoji.
  #
  # curl -d "secret=a&comment=test_0&repo=org/repo&issue=2" http://0.0.0.0:3000/comment
  #
  # repo must be in the form of: user/repo
  post '/comment' do
    
    # validate secret
    halt 404 unless params[:secret] == @@secret
   
    repo = params[:repo]
    issue = params[:issue]
    
    # ensure we're on the last SHA of the pull request
    sha = params[:sha]
    halt 400 unless sha == get_last_sha( repo, issue )

    response = @@connection.post do | request |
      request.url "repos/#{repo}/issues/#{issue}/comments"
      request.headers['Authorization'] = "token #{@@token}"

      comment = params[:comment]
      request.body = MultiJson.dump({:body => comment})
    end

    if @@debug
      ap response.env
      ap MultiJson.load(response.env[:body])
    end

    return if response.env[:status] != 201
    
    # Remove old comments now that there's a new comment.
    remove repo, issue

    # Store new comment id
    body = MultiJson.load(response.env[:body])
    comment_id = body['id']
    add issue, comment_id
  end

  get '/*' do
    halt 404
  end

end # class Comment