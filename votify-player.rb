# coding: utf-8
require 'monitor'

module Hallon
  # A wrapper around Session for playing, stopping and otherwise
  # controlling the playback features of libspotify.
  #
  # @see Session
  class VotifyPlayer < Base
    # meep?
    extend Observable::Player

    # @return [Spotify::Session] session pointer
    attr_reader :pointer

    # @return [Symbol] one of :playing, :paused, :stopped
    attr_reader :status

    # @return [Array<Symbol>] a list of available playback bitrates.
    def self.bitrates
      Spotify.enum_type(:bitrate).symbols.sort_by do |sym|
        # sort by bitrate quality
        sym.to_s.to_i
      end
    end

    # Constructs a Player, given an audio driver.
    #
    # @example
    #   player = Hallon::Player.new(Hallon::OpenAL)
    #   player.play(track)
    #
    # @note for instructions on how to write your own audio driver, see Hallons’ README
    # @param [AudioDriver] driver
    # @yield instance_evals itself, allowing you to define callbacks using `on`
    def initialize(driver, &block)
      @session = Hallon::Session.instance
      @pointer = @session.pointer

      # sample rate is often (if not always) 44.1KHz, so
      # we keep an audio queue that can store 3s of audio
      @queue  = AudioQueue.new(44100)
      @driver = driver.new
      @driver.format = { rate: 44100, channels: 2, type: :int16 }

      # used for feeder thread to know if it should stream
      # data to the driver or not (see #status=)
      @status_c = @queue.new_cond
      # set initial status (we assume stopped)
      self.status = :stopped

      # this thread feeds the audio driver with data, but
      # if we are not playing it’ll wait until we are

      ####----------->> Changed from the original hallon player.rb for converting to mp3
      file = File.open('./tmp/riptastic.raw', 'a')

      @thread = Thread.start(@driver, @queue, @status_c) do |output, queue, cond|
        output.stream do |num_frames|
          queue.synchronize do
            frames = queue.pop(output.format, *num_frames)

            if frames.nil?
              # if we received no frames, it means the audio format changed
              output.format = queue.format
            end

            ####----------->> Changed from the original hallon player.rb for converting to mp3
            ruby_audio = frames.to_a.flatten
            audio_data = ruby_audio.collect!{|a| a.to_i}.pack("s*")
            file << audio_data

            # frames is either nil, or an array of audio frames
            frames
          end
        end
      end

      @session.on(:start_playback, &method(:start_playback))
      @session.on(:stop_playback,  &method(:stop_playback))
      @session.on(:music_delivery, &method(:music_delivery))
      @session.on(:get_audio_buffer_stats, &method(:get_audio_buffer_stats))

      @session.on(:end_of_track)    { |*args| trigger(:end_of_track, *args) }
      @session.on(:streaming_error) { |*args| trigger(:streaming_error, *args) }
      @session.on(:play_token_lost) { |*args| trigger(:play_token_lost, *args) }

      instance_eval(&block) if block_given?
    end

    protected

    # Called by libspotify when the driver should start audio playback.
    #
    # Will be called after calling our buffers are full enough to support
    # continous playback.
    def start_playback
      self.status = :playing
    end

    # Called by libspotify when the driver should pause audio playback.
    #
    # Might happen if we’re playing audio faster than we can stream it.
    def stop_playback
      self.status = :paused
    end

    # Called by libspotify on music delivery; format is
    # a hash of (sample) rate, channels and (sample) type.
    def music_delivery(format, frames)
      # File.open('./tmp/log.raw', 'a') << frames
      @queue.synchronize do
        @queue.clear if frames.none?
        @queue.push(format, frames)
      end
    end

    # Called by libspotify to request information about our
    # audio buffer. Required if we want libspotify to tell
    # us when we should start and stop playback.
    def get_audio_buffer_stats
      drops = @driver.drops if @driver.respond_to?(:drops)
      [@queue.size, drops.to_i]
    end

    # This is essentially a mini state machine. Setting the
    # status will also put the driver in the correct mode, as
    # well as allow audio data to stream through the feeder
    # thread.
    #
    # @param [Symbol] new_status one of :playing, :paused, :stopped
    # @raise [ArgumentError] if given an invalid status
    def status=(new_status)
      @queue.synchronize do
        old_status, @status = status, new_status

        case status
        when :playing
          @driver.play
        when :paused
          @driver.pause
        when :stopped
          # TODO: even if we clear and stop here, the music_delivery
          # callback might be waiting for ruby to allow it to callback,
          # which will result in us getting old audio frames when we
          # play the next song. I don’t have a good solution yet.
          @queue.clear
          @driver.stop
        else
          @status = old_status
          raise ArgumentError, "invalid status"
        end

        @status_c.signal
      end
    end

    public

    # @note default output also shows all our instance variables, that
    #       is kind of unnecessary and might take some time to display,
    #       for example if the audio queue is full
    # @return [String]
    def to_s
      name    = self.class.name
      address = pointer.address.to_s(16)
      "<#{name} session=0x#{address} driver=#{@driver.class} status=#{status}>"
    end

    # Start playing the currently loaded, or given, Track.
    #
    # @example
    #   player.play("spotify:track:44FHDONpdYeDpmqyS3BLRP")
    #
    # @note If no track is given, will try to play currently {#load}ed track.
    # @param [Track, Link, String, nil] track
    # @return [Player]
    def play(track = nil)
      load(track) unless track.nil?
      tap { Spotify.session_player_play(pointer, true) }
    end

    # Pause playback of a Track.
    #
    # @return nothing
    def pause
      self.status = :paused
      Spotify.session_player_play(pointer, false)
    end

    # Stop playing current track and unload it.
    #
    # @return nothing
    def stop
      self.status = :stopped
      Spotify.session_player_unload(pointer)
    end

    # Like {#play}, but blocks until the track has finished playing.
    #
    # @param (see #play)
    # @return (see #play)
    def play!(track = nil)
      end_of_track = false
      old_callback = on(:end_of_track) { end_of_track = true }
      play(track)
      wait_for(:end_of_track) { end_of_track }
    ensure
      on(:end_of_track, &old_callback)
    end

    # Set preferred playback bitrate.
    #
    # @note the double possible errors is a result of the same thing as for
    #       {Session#offline_bitrate=}, see its documentation for further information.
    #
    # @raise [ArgumentError] if given invalid bitrate
    # @raise [Spotify::Error] if libspotify does not accept the given bitrate
    # @param [Symbol] bitrate one of :96k, :160k, :320k
    def bitrate=(bitrate)
      Spotify.try(:session_preferred_bitrate, pointer, bitrate)
    end

    # Loads a Track for playing.
    #
    # @param [Track, Link, String] track
    # @return [Player]
    # @raise [Error] if the track could not be loaded
    def load(track)
      track = Track.new(track) unless track.is_a?(Track)
      error = Spotify.session_player_load(pointer, track.pointer)
      tap { Error.maybe_raise(error) }
    end

    # Prepares a Track for playing, without {#load}ing it.
    #
    # @note You can only prefetch if caching is on.
    # @param [Track] track
    # @return [Player]
    def prefetch(track)
      error = Spotify.session_player_prefetch(pointer, track.pointer)
      tap { Error.maybe_raise(error) }
    end

    # Seek to the desired position of the currently loaded Track.
    #
    # @param [Numeric] seconds offset position in seconds
    # @return [Player]
    def seek(seconds)
      tap { Spotify.session_player_seek(pointer, seconds * 1000) }
    end

    # @return [Boolean] true if libspotify is set to normalize audio volume.
    def volume_normalization?
      Spotify.session_get_volume_normalization(pointer)
    end

    # @param [Boolean] normalize_volume true if libspotify should normalize audio volume.
    def volume_normalization=(normalize_volume)
      Spotify.session_set_volume_normalization(pointer, !! normalize_volume)
    end
  end
end
