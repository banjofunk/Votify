require 'sinatra'
require "sinatra/streaming"
require 'haml'
require './votify-jukebox'
require './votify-search'
require './votify-player'
require 'lame_encoder'

get '/stream' do
  haml :player_new, :layout => false
end

get '/stream-data' do
  stream(:keep_open) do |out|
    l = LameEncoder.new
    l.input_raw(44.1)
    l.mode(:stereo)
    l.input_file('./tmp/riptastic.raw')
    l.output_file('./public/spot_rip.mp3')
    # l.input_file('-')
    # l.output_file('./public/spot_rip.mp3')
    l.convert!
  end
end

get '/' do
  haml :search
end

get '/search/:search' do
  votify_search = VotifySearch.new
  results = votify_search.lookup params[:search]

  @artists = results[:artists]
  @albums = results[:albums]
  @tracks = results[:tracks]

  haml :_search, :layout => false
end

get '/select/artist/:artist' do
  votify_search = VotifySearch.new
  results = votify_search.artist_select params[:artist]
  
  @artist = results[:artist]
  @albums = results[:albums]
  @tracks = results[:top_hits]
  haml :_artist, :layout => false
end

get '/select/album/:album' do

  votify_search = VotifySearch.new
  results = votify_search.album_select(params[:album])
  puts "---- results -----> #{results}"
  
  @artist = results[:artist]
  @album = results[:album]
  @tracks = results[:tracks] 
  haml :_album, :layout => false
end

get '/play/track/:track' do
  juke = Jukebox.new
  juke.play params[:track]
end
