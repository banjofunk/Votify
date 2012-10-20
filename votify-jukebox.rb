require 'hallon'
require 'hallon-openal'
require './votify_audio_driver'

class Jukebox

  def initialize
    begin 
      Hallon::Session.instance
    rescue 
      session = Hallon::Session.initialize(IO.read('./spotify_appkey.key'))
      session.login!('joshsfunkybanjo', 'skiing1')
    end
    # @player = Hallon::Player.new(Hallon::OpenAL)
    @player = Hallon::VotifyPlayer.new(Hallon::VotifyAudioDriver)
  end

  def play(uri = nil)
    track = uri ? Hallon::Track.new(uri).load : ""
    @player.play(track)
  end

  def pause
    @player.pause
  end
end
