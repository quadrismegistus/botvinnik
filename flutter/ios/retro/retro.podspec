#
# The retro engines as a static archive, for the platform that cannot spawn
# them.
#
# The archives are BUILT, not committed (../../stage-ios-engines.sh), which is
# why the Podfile only declares this pod when they are present — the same
# arrangement as the macOS binaries: a build that skipped staging does not
# offer retro at all, rather than offering it and silently playing Stockfish.
#
# Two things here are less obvious than they look:
#
#   * **-force_load, not a vendored library.** dart:ffi looks the symbols up at
#     runtime with DynamicLibrary.process(), so nothing in the link graph
#     references them and the linker strips the archive to nothing — leaving an
#     app that contains the whole engine and reports retro unsupported.
#   * **[sdk=…]-conditional, not an xcframework.** The device and simulator
#     slices are both arm64, so they cannot be lipo'd into one file, and
#     CocoaPods does not generate a copy phase for an xcframework of static
#     libraries under use_frameworks!. Choosing the path per SDK is the plain
#     way to say the same thing.
#
# The engines are morlock (MIT); Go's runtime travels with them under
# BSD-3-Clause. Both are recorded in THIRD-PARTY-NOTICES.md.
#
Pod::Spec.new do |s|
  s.name             = 'retro'
  s.version          = '0.0.1'
  s.summary          = 'TUROCHAMP, BERNSTEIN and SARGON as a Go c-archive.'
  s.description      = <<-DESC
morlock's re-implementations of three historical chess engines, built with
-buildmode=c-archive so dart:ffi can drive them where child processes are not
available.
                       DESC
  s.homepage         = 'https://github.com/herohde/morlock'
  s.license          = { :type => 'MIT', :file => 'LICENSE' }
  s.author           = { 'Henning Rohde' => 'noreply@github.com' }
  s.source           = { :path => '.' }
  s.platform         = :ios, '13.0'
  s.static_framework = true

  # Go's runtime needs both on darwin.
  s.frameworks = 'CoreFoundation', 'Security'

  s.preserve_paths = 'lib/**/*', 'include/**/*'
  s.user_target_xcconfig = {
    'OTHER_LDFLAGS[sdk=iphoneos*]' =>
      '-force_load "${PODS_ROOT}/../retro/lib/device/libmorlock.a"',
    'OTHER_LDFLAGS[sdk=iphonesimulator*]' =>
      '-force_load "${PODS_ROOT}/../retro/lib/sim/libmorlock.a"'
  }
end
