module GC
  def self.stat(all_stats = {})
    require 'java'
    gc_beans = java.lang.management.ManagementFactory.garbage_collector_mx_beans
    pool_beans = {}
    java.lang.management.ManagementFactory.memory_pool_mx_beans.each do |pool_bean|
      pool_beans[pool_bean.name] = pool_bean
    end

    all_stats.merge!({
        :count => 0,
        :time => 0,
        :committed => 0.0,
        :init => 0.0,
        :max => 0.0,
        :used => 0.0,
        :peak_committed => 0.0,
        :peak_init => 0.0,
        :peak_max => 0.0,
        :peak_used => 0.0,
        :last_committed => 0.0,
        :last_init => 0.0,
        :last_max => 0.0,
        :last_used => 0.0
    })

    gc_beans.each do |gc_bean|
      gc_stats = all_stats[gc_bean.name] = {}
      all_stats[:count] += gc_stats[:count] = gc_bean.collection_count
      all_stats[:time] += gc_stats[:time] = gc_bean.collection_time

      gc_bean.memory_pool_names.each do |pool_name|
        pool_bean = pool_beans[pool_name]

        all_pools = gc_stats[:pools] = {}
        pool_stats = all_pools[pool_name] = {}

        usage = pool_bean.usage
        peak_usage = pool_bean.peak_usage
        last_usage = pool_bean.collection_usage

        all_stats[:committed] += pool_stats[:committed] = usage.committed
        all_stats[:init] += pool_stats[:init] = usage.init
        all_stats[:max] += pool_stats[:max] = usage.max
        all_stats[:used] += pool_stats[:used] = usage.used
        all_stats[:peak_committed] += pool_stats[:peak_committed] = peak_usage.committed
        all_stats[:peak_init] += pool_stats[:peak_init] = peak_usage.init
        all_stats[:peak_max] += pool_stats[:peak_max] = peak_usage.max
        all_stats[:peak_used] += pool_stats[:peak_used] = peak_usage.used
        all_stats[:last_committed] += pool_stats[:last_committed] = last_usage.committed
        all_stats[:last_init] += pool_stats[:last_init] = last_usage.init
        all_stats[:last_max] += pool_stats[:last_max] = last_usage.max
        all_stats[:last_used] += pool_stats[:last_used] = last_usage.used
      end
    end

    all_stats
  end

  begin
    require 'java'
    java.lang.Class.forName('com.sun.management.GarbageCollectionNotificationInfo')

    # class exists, proceed with GC notification version
    module Profiler
      HEADER = "   ID  Type                      Timestamp(sec)    Before(kB)     After(kB)    Delta(kB)        Heap(kB)          GC Time(ms) "
      FORMAT = "%5d  %-20s %19.4f %13i %13i %12i %15i %20.10f"

      class GCListener
        include javax.management.NotificationListener

        def initialize
          @lines = []
        end

        attr_accessor :lines

        def handleNotification(notification, o)
          lines << notification
        end

        def clear
          lines.clear
        end
      end

      def self.enabled?
        @gc_beans != nil
      end

      def self.enable
        require 'java'
        @gc_listener ||= GCListener.new
        java.lang.management.ManagementFactory.garbage_collector_mx_beans.each do |gc_bean|
          gc_bean.add_notification_listener @gc_listener, nil, nil
        end
      end

      def self.disable
        require 'java'
        java.lang.management.ManagementFactory.garbage_collector_mx_beans.each do |gc_bean|
          gc_bean.remove_notification_listener @gc_listener
        end
      end

      def self.clear
        @gc_listener.clear
      end

      def self.report
        puts result
      end

      def self.result
        lines = @gc_listener.lines.dup

        counts = Hash.new(0)
        report_lines = []

        lines.each_with_index do |line, i|
          report_lines << HEADER if i % 20 == 0

          gc_notification = com.sun.management.GarbageCollectionNotificationInfo.from(line.user_data)
          gc_info = gc_notification.gc_info

          mem_before = gc_info.memory_usage_before_gc
          mem_after = gc_info.memory_usage_after_gc

          after = 0
          before = 0
          commit = 0

          mem_after.entry_set.each do |entry|
            name = entry.key

            before_usage = mem_before[name]
            before += before_usage.used

            after_usage = entry.value
            after += after_usage.used

            commit += after_usage.committed
          end

          counts[gc_notification.gc_name] += 1

          report_lines << sprintf(
                   FORMAT,
                   gc_info.id,
                   gc_notification.gc_name,
                   gc_info.start_time/1000000.0,
                   before / 1024,
                   after / 1024,
                   (before - after) / 1024,
                   commit / 1024,
                   gc_info.duration/1000.0)
        end

        "GC: #{counts.map{|k,v| "#{v} #{k}"}.join(', ')}\n" + report_lines.join("\n")
      end

      def self.total_time
        duration = 0

        @gc_listener.lines.each_with_index do |line, i|
          puts HEADER if i % 20 == 0

          gc_notification = com.sun.management.GarbageCollectionNotificationInfo.from(line.user_data)
          gc_info = gc_notification.gc_info

          duration += gc_info.duration
        end

        return duration / 1000.0
      end
    end

  rescue java.lang.ClassNotFoundException # loading GarbageCollectionNotificationInfo

    # No GC notifications, use polled version
    module Profiler
      def self.enabled?
        @gc_beans != nil
      end

      def self.enable
        require 'java'
        @gc_beans ||= java.lang.management.ManagementFactory.garbage_collector_mx_beans
        clear
      end

      def self.disable
        @gc_beans = nil
      end

      def self.clear
        return unless @gc_beans

        time = 0
        @gc_beans.each do |gc_bean|
          time += gc_bean.collection_time
        end
        @start_time = time
      end

      def self.result
        nil
      end

      def self.report
        nil
      end

      def self.total_time
        time = 0
        @gc_beans.each do |gc_bean|
          time += gc_bean.collection_time
        end
        (time - @start_time) / 1000.0
      end
    end
  end
end