require 'sinatra'

require_relative './common.rb'
require 'pry'

class MyApp < Sinatra::Base
  configure :development do
    # register Sinatra::Reloader
  end

  # Your modular application code goes here...
end


def en
  @enclient ||= ENClient.new
end

get '/inbox' do
  notes = en.inbox_notes

  notes.map { |note|
    { title: note.title,
      guid: note.guid}
  }.to_json
end

get '/notes/:guid' do |r|
  note = en.get_full_note_by_guid(r)
  ({
    guid: note.guid,
    title: note.title,
    content: note.content
  }).to_json
end

get '/refile-targets/' do
  targets = en.refile_targets
  targets.map { |t|
    id, note = t
    {
      title: note.title,
      guid: note.guid
    }
  }.to_json
end
