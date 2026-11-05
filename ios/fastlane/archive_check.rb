# The archive check's pure parts: which binaries an app bundle runs code
# from, and the verdict on each slice of one from its load commands. The
# Fastfile requires this file; `ruby archive_check_test.rb` runs its tests.
require "shellwords"

module ArchiveCheck
  # The CPU architectures an iOS device runs. A slice marked only with
  # LC_VERSION_MIN_IPHONEOS (the form before LC_BUILD_VERSION) is a device
  # build only on one of these: legacy simulator slices carried the same
  # command on x86_64 and i386.
  DEVICE_ARCHS = %w[arm64 arm64e armv7 armv7s].freeze

  # The executable of a bundle (an app, a framework, an app extension),
  # named by its Info.plist; nil when the plist or the key is missing.
  def self.bundle_executable(bundle)
    plist = File.join(bundle, "Info.plist")
    return nil unless File.file?(plist)
    name = `/usr/libexec/PlistBuddy -c 'Print CFBundleExecutable' #{plist.shellescape} 2>/dev/null`.strip
    name.empty? ? nil : File.join(bundle, name)
  end

  # Every binary the archive runs code from, as [bundle or file, binary]:
  # the app, its frameworks, its app extensions and their frameworks, and
  # every bare dylib under any of those Frameworks directories.
  def self.binaries(app)
    bundles = [app] + Dir.glob("#{app}/Frameworks/*.framework").sort
    dylib_dirs = ["#{app}/Frameworks"]
    Dir.glob("#{app}/PlugIns/*.appex").sort.each do |appex|
      bundles << appex
      bundles += Dir.glob("#{appex}/Frameworks/*.framework").sort
      dylib_dirs << "#{appex}/Frameworks"
    end
    list = bundles.map { |b| [b, bundle_executable(b)] }
    dylib_dirs.each do |dir|
      Dir.glob("#{dir}/*.dylib").sort.each { |f| list << [f, f] }
    end
    list
  end

  # The slices of `otool -arch all -l` output, as [arch, text]. otool heads
  # each slice with "<path> (architecture <arch>):"; output with no such
  # head is read as one slice of unknown architecture.
  def self.slices(load_commands)
    parts = load_commands.split(/^.*\(architecture (\S+)\):\n/)
    return [["unknown", load_commands]] if parts.size == 1
    parts.shift
    parts.each_slice(2).map { |arch, text| [arch, text.to_s] }
  end

  # Why one slice is not an iOS device build, or nil when it is.
  # LC_BUILD_VERSION names the platform (2, or ios, is the device; 7 is the
  # simulator). The older LC_VERSION_MIN_IPHONEOS passes only on a device
  # architecture. A slice with neither is refused.
  def self.slice_problem(arch, text)
    platforms = text.scan(/LC_BUILD_VERSION.*?platform (\S+)/m).flatten
    if platforms.any?
      bad = platforms.reject { |p| p == "2" || p.downcase == "ios" }
      return bad.empty? ? nil : "platform #{bad.uniq.join(',')}"
    end
    if text.include?("LC_VERSION_MIN_IPHONEOS")
      return DEVICE_ARCHS.include?(arch) ? nil : "min-iphoneos on #{arch}"
    end
    "no build version"
  end

  # The problems of one binary from its load commands, one entry per slice
  # that is not an iOS device build; empty when every slice is.
  def self.problems(load_commands)
    slices(load_commands).filter_map do |arch, text|
      problem = slice_problem(arch, text)
      problem && "#{arch}: #{problem}"
    end
  end
end
