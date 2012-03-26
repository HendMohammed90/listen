module Listen
  class Listener
    attr_reader :directory, :directory_record, :adapter

    # The default value for using relative paths in the callback.
    DEFAULT_TO_RELATIVE_PATHS = false

    # Initialize the directory listener.
    #
    # @param [String] directory the directory to listen to
    # @param [Hash] options the listen options
    # @option options [String] ignore a list of paths to ignore
    # @option options [Regexp] filter a list of regexps file filters
    # @option options [Float] latency the delay between checking for changes in seconds
    # @option options [Boolean] relative_paths whether or not to use relative-paths in the callback
    # @option options [Boolean] force_polling whether to force the polling adapter or not
    # @option options [String, Boolean] polling_fallback_message to change polling fallback message or remove it
    #
    # @yield [modified, added, removed] the changed files
    # @yieldparam [Array<String>] modified the list of modified files
    # @yieldparam [Array<String>] added the list of added files
    # @yieldparam [Array<String>] removed the list of removed files
    #
    def initialize(directory, options = {}, &block)
      @block              = block
      @directory          = directory
      @directory_record   = DirectoryRecord.new(directory)
      @use_relative_paths = DEFAULT_TO_RELATIVE_PATHS

      @use_relative_paths = options.delete(:relative_paths) if options[:relative_paths]
      @directory_record.ignore(*options.delete(:ignore))    if options[:ignore]
      @directory_record.filter(*options.delete(:filter))    if options[:filter]

      @adapter_options = options
    end

    # Starts the listener by initializing the adapter and building
    # the directory record concurrently, then it starts the adapter to watch
    # for changes.
    #
    # @param [Boolean] blocking whether or not to block the current thread after starting
    #
    def start(blocking = true)
      t = Thread.new { @adapter = initialize_adapter }
      @directory_record.build
      t.join
      @adapter.start(blocking)
    end

    # Stops the listener.
    #
    def stop
      @adapter.stop
    end

    # Pauses the listener.
    #
    # @return [Listen::Listener] the listener
    #
    def pause
      @adapter.paused = true
      self
    end

    # Unpauses the listener.
    #
    # @return [Listen::Listener] the listener
    #
    def unpause
      @directory_record.build
      @adapter.paused = false
      self
    end

    # Returns whether the listener is paused or not.
    #
    # @return [Boolean] adapter paused status
    #
    def paused?
      !!@adapter && @adapter.paused == true
    end

    # Add ignored path to the listener.
    #
    # @param (see Listen::DirectoryRecord#ignore)
    #
    # @return [Listen::Listener] the listener
    #
    def ignore(*paths)
      @directory_record.ignore(*paths)
      self
    end

    # Add file filters to the listener.
    #
    # @param (see Listen::DirectoryRecord#filter)
    #
    # @return [Listen::Listener] the listener
    #
    def filter(*regexps)
      @directory_record.filter(*regexps)
      self
    end

    # Sets the latency for the adapter. This is a helper method
    # to simplify changing the latency directly from the listener.
    #
    # @example Wait 0.5 seconds each time before checking changes
    #   latency 0.5
    #
    # @param [Float] seconds the amount of delay, in seconds
    #
    # @return [Listen::Listener] the listener
    #
    def latency(seconds)
      @adapter_options[:latency] = seconds
      self
    end

    # Defines whether the use of the polling adapter
    # should be forced or not.
    #
    # @example Forcing the use of the polling adapter
    #   force_polling true
    #
    # @param [Boolean] value whether to force the polling adapter or not
    #
    # @return [Listen::Listener] the listener
    #
    def force_polling(value)
      @adapter_options[:force_polling] = value
      self
    end

    # Defines a custom polling fallback message of disable it.
    #
    # @example Disabling the polling fallback message
    #   polling_fallback_message false
    #
    # @param [String, Boolean] value to change polling fallback message or remove it
    #
    # @return [Listen::Listener] the listener
    #
    def polling_fallback_message(value)
      @adapter_options[:polling_fallback_message] = value
      self
    end

    # Sets the callback that gets called on changes.
    #
    # @example Assign a callback to be called on changes
    #   callback = lambda { |modified, added, removed| ... }
    #   change &callback
    #
    # @param [Proc] block the callback proc
    #
    # @return [Listen::Listener] the listener
    #
    def change(&block) # modified, added, removed
      @block = block
      self
    end

    # Runs the callback passing it the changes if there are any.
    #
    # @param (see Listen::DirectoryRecord#fetch_changes)
    #
    def on_change(directories, options = {})
      changes = @directory_record.fetch_changes(directories, options.merge(
        :relative_paths => @use_relative_paths
      ))
      unless changes.values.all? { |paths| paths.empty? }
        @block.call(changes[:modified],changes[:added],changes[:removed])
      end
    end

    private

    # Initializes an adapter passing it the callback and adapters' options.
    #
    def initialize_adapter
      callback = lambda { |changed_dirs, options| self.on_change(changed_dirs, options) }
      Adapter.select_and_initialize(@directory, @adapter_options, &callback)
    end
  end
end
