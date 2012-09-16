require 'hallon'

class VotifySearch
  def initialize
    begin 
      Hallon::Session.instance
    rescue 
      session = Hallon::Session.initialize(IO.read('./spotify_appkey.key'))
      session.login!('joshsfunkybanjo', 'skiing1')
    end
  end
  
  def lookup(search_phrase)
    search = Hallon::Search.new search_phrase
    search.load
  
    artists = search.artists.to_a
    artists.map(&:load)
    albums = search.albums.to_a
    albums.map(&:load)
    tracks = search.tracks.to_a
    tracks.map(&:load)
    
    results = {}
    results[:artists] = artists
    results[:albums] = albums
    results[:tracks] = tracks
    results
  end

  def artist_select(artist_link)
    artist = Hallon::Artist.new artist_link
    artist_browse = artist.browse.load
    albums = artist_browse.albums.to_a
    albums.map(&:load)
    top_hits = artist_browse.top_hits.to_a
    top_hits.map(&:load)
    results = {}
    results[:artist] = artist_browse
    results[:albums] = albums
    results[:top_hits] = top_hits
    results
  end

  def album_select(album_link)
    album = Hallon::Album.new album_link
    album_browse = album.browse.load
    tracks = album_browse.tracks.to_a
    tracks.map(&:load)
    results = {}
    if album_browse.artist.name == 'Various Artists'
      results[:artist] = album.load.tracks.first.artist.browse.load
    else
      results[:artist] = album_browse.artist.browse.load
    end
    results[:album] = album_browse.album
    results[:tracks] = tracks
    results
  end
end
