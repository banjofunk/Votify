require 'sinatra'
require 'haml'
require './votify-jukebox'
require './votify-search'

get '/test' do
  stream do |out|
    out << "It's gonna be legen -\n"
    sleep 0.5
    out << " (wait for it) \n"
    sleep 1
    out << "- dary!\n"
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
