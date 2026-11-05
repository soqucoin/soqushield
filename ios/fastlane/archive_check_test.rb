# The archive check's slice verdicts and binary listing, on fixtures shaped
# like `otool -arch all -l` output: ruby archive_check_test.rb
require "minitest/autorun"
require "tmpdir"
require "fileutils"
require_relative "archive_check"

class ArchiveCheckTest < Minitest::Test
  DEVICE = "/x/App (architecture arm64):\nLoad command 8\n      cmd LC_BUILD_VERSION\n  cmdsize 32\n platform 2\n    minos 13.0\n".freeze
  SIMULATOR = "/x/App (architecture arm64):\n      cmd LC_BUILD_VERSION\n platform 7\n    minos 13.0\n".freeze
  LEGACY_DEVICE = "/x/App (architecture armv7):\n      cmd LC_VERSION_MIN_IPHONEOS\n  version 9.0\n".freeze
  LEGACY_SIMULATOR = "/x/App (architecture x86_64):\n      cmd LC_VERSION_MIN_IPHONEOS\n  version 9.0\n".freeze
  NO_VERSION = "/x/App (architecture arm64):\n      cmd LC_SEGMENT_64\n".freeze

  def test_a_device_slice_passes
    assert_empty ArchiveCheck.problems(DEVICE)
  end

  def test_a_named_platform_passes
    assert_empty ArchiveCheck.problems(DEVICE.sub("platform 2", "platform IOS"))
  end

  def test_a_simulator_slice_fails
    assert_equal ["arm64: platform 7"], ArchiveCheck.problems(SIMULATOR)
  end

  def test_a_legacy_device_slice_passes
    assert_empty ArchiveCheck.problems(LEGACY_DEVICE)
  end

  def test_a_legacy_simulator_slice_fails
    assert_equal ["x86_64: min-iphoneos on x86_64"], ArchiveCheck.problems(LEGACY_SIMULATOR)
  end

  def test_a_slice_with_no_version_command_fails
    assert_equal ["arm64: no build version"], ArchiveCheck.problems(NO_VERSION)
  end

  def test_each_slice_of_a_fat_binary_is_judged_on_its_own
    # A device slice beside a legacy simulator slice: the whole-output form
    # saw platform 2 and passed the binary.
    assert_equal ["x86_64: min-iphoneos on x86_64"], ArchiveCheck.problems(DEVICE + LEGACY_SIMULATOR)
    assert_equal ["arm64: platform 7"], ArchiveCheck.problems(DEVICE + SIMULATOR)
    assert_empty ArchiveCheck.problems(DEVICE + LEGACY_DEVICE)
  end

  def test_output_with_no_slice_head_is_one_slice_of_unknown_architecture
    assert_empty ArchiveCheck.problems("      cmd LC_BUILD_VERSION\n platform 2\n")
    assert_equal ["unknown: min-iphoneos on unknown"],
                 ArchiveCheck.problems("      cmd LC_VERSION_MIN_IPHONEOS\n  version 9.0\n")
  end

  def test_binaries_cover_the_app_its_frameworks_its_extensions_and_every_bare_dylib
    Dir.mktmpdir do |dir|
      app = File.join(dir, "Payload", "Runner.app")
      bundle(app, "Runner")
      bundle(File.join(app, "Frameworks", "A.framework"), "A")
      touch(File.join(app, "Frameworks", "x.dylib"))
      appex = File.join(app, "PlugIns", "E.appex")
      bundle(appex, "E")
      bundle(File.join(appex, "Frameworks", "B.framework"), "B")
      touch(File.join(appex, "Frameworks", "y.dylib"))
      bundle(File.join(app, "Frameworks", "NoExec.framework"), nil)

      found = ArchiveCheck.binaries(app).map { |bundle, bin| [bundle.sub(app + "/", ""), bin && bin.sub(app + "/", "")] }
      assert_equal [
        [app, "Runner"],
        ["Frameworks/A.framework", "Frameworks/A.framework/A"],
        ["Frameworks/NoExec.framework", nil],
        ["PlugIns/E.appex", "PlugIns/E.appex/E"],
        ["PlugIns/E.appex/Frameworks/B.framework", "PlugIns/E.appex/Frameworks/B.framework/B"],
        ["Frameworks/x.dylib", "Frameworks/x.dylib"],
        ["PlugIns/E.appex/Frameworks/y.dylib", "PlugIns/E.appex/Frameworks/y.dylib"],
      ], found
    end
  end

  private

  def touch(path)
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, "")
  end

  # A bundle with an Info.plist naming [executable] (or naming none).
  def bundle(path, executable)
    FileUtils.mkdir_p(path)
    body = executable ? "\t<key>CFBundleExecutable</key>\n\t<string>#{executable}</string>\n" : ""
    File.write(File.join(path, "Info.plist"), <<~PLIST)
      <?xml version="1.0" encoding="UTF-8"?>
      <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
      <plist version="1.0">
      <dict>
      #{body}</dict>
      </plist>
    PLIST
    touch(File.join(path, executable)) if executable
  end
end
