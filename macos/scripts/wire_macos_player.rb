#!/usr/bin/env ruby
# Wires the AetherEngine playback stack into the macOS Runner project:
# - adds macos/Runner/Playback/*.swift and the shared tvOS Aether wrapper
#   layer to the Runner target
# - adds the AetherEngine SPM package (AETHER_LOCAL=1 uses the sibling
#   checkout at ../../AetherEngine for development)
# - adds the standalone libass package for host-side ASS rendering
# - raises the deployment target to the engine's macOS floor
# Idempotent. Run after project regeneration or when Playback/ files change.
require 'xcodeproj'

project_dir = File.expand_path(File.join(__dir__, '..'))
project_path = File.join(project_dir, 'Runner.xcodeproj')
project = Xcodeproj::Project.open(project_path)
target = project.targets.find { |t| t.name == 'Runner' } or abort('Runner target not found')

playback_group = project.main_group.find_subpath('Runner/Playback', true)
playback_group.set_source_tree('SOURCE_ROOT')
playback_group.set_path('Runner/Playback')

source_exts = %w[.swift .c .m .mm]
abs_files = Dir.glob(File.join(project_dir, 'Runner/Playback/**/*'))
  .select { |f| source_exts.include?(File.extname(f)) }.sort

# The engine wrapper layer is shared with the iOS and tvOS targets and lives
# in the tvOS tree. Platform deltas are #if guarded inside the files.
shared_dir = File.expand_path(
  File.join(project_dir, '..', 'tvos', 'Runner', 'Playback', 'Aether'))
abs_files += Dir.glob(File.join(shared_dir, '*.swift')).sort
# The preview and theme music channels live beside the tvOS runner and serve
# every Apple platform, so macOS plays trailers and theme music through
# AVFoundation rather than a second media stack.
shared_channels = File.expand_path(File.join(project_dir, '..', 'tvos', 'Runner'))
abs_files += %w[AppleTvPreviewChannel.swift AppleTvThemeMusicChannel.swift]
  .map { |name| File.join(shared_channels, name) }
  .select { |path| File.exist?(path) }
basenames = abs_files.map { |f| File.basename(f) }

# Drop references this script is about to re-add, and any left pointing at a
# playback file that no longer exists.
playback_root = File.join(project_dir, 'Runner/Playback')
project.files.select do |f|
  next true if basenames.include?(File.basename(f.path.to_s))
  begin
    path = f.real_path.to_s
    path.start_with?(playback_root) && !File.exist?(path)
  rescue StandardError
    false
  end
end.each do |f|
  f.referrers.grep(Xcodeproj::Project::Object::PBXBuildFile).each(&:remove_from_project)
  f.remove_from_project
end

abs_files.each do |abs|
  ref = playback_group.new_reference(abs)
  target.add_file_references([ref]) unless File.extname(abs) == '.h'
  puts "added source: #{File.basename(abs)}"
end

# --- AetherEngine ---
# Pinned to a revision of the fork, which carries client certificate support,
# a frame timing fix and the Dolby Vision FEL curve fold that upstream doesn't
# ship. An engine bump is a deliberate change rather than
# something a resolve should pick up on its own.
aether_remote_url = 'https://github.com/RadicalMuffinMan/AetherEngine'
aether_revision = '34f149ba2dd483f490dca13a5a3027d58a9956f5'
aether_local_path = File.expand_path(File.join(project_dir, '..', '..', 'AetherEngine'))
use_local_aether = ENV['AETHER_LOCAL'] == '1'

if use_local_aether && !File.directory?(aether_local_path)
  abort("AETHER_LOCAL=1 but no checkout at #{aether_local_path}")
end

# By default the Runner reaches the engine through the local package
# macos/AetherEngineTraits (wired below), which pins the revision and turns on
# the engine's optional components. A second, direct reference to the same
# package beside it makes Xcode's package resolution fail, so remove any.
# AETHER_LOCAL=1 links the sibling checkout directly instead (no traits).
project.root_object.package_references.dup.each do |p|
  is_remote_aether = p.respond_to?(:repositoryURL) &&
                     File.basename(p.repositoryURL.to_s.chomp('/'), '.git') == 'AetherEngine'
  is_local_aether = p.is_a?(Xcodeproj::Project::Object::XCLocalSwiftPackageReference) &&
                    File.basename(p.relative_path.to_s) == 'AetherEngine'
  next unless is_remote_aether || (is_local_aether && !use_local_aether)
  target.package_product_dependencies.dup.each do |d|
    next unless d.package&.uuid == p.uuid
    d.referrers.grep(Xcodeproj::Project::Object::PBXBuildFile).each(&:remove_from_project)
    target.package_product_dependencies.delete(d)
    d.remove_from_project
  end
  project.root_object.package_references.delete(p)
  p.remove_from_project
  puts 'removed direct AetherEngine package reference'
end

if use_local_aether
  aether_pkg = project.root_object.package_references.find do |p|
    p.is_a?(Xcodeproj::Project::Object::XCLocalSwiftPackageReference) &&
      File.basename(p.relative_path.to_s) == 'AetherEngine'
  end
  unless aether_pkg
    aether_pkg = project.new(Xcodeproj::Project::Object::XCLocalSwiftPackageReference)
    aether_pkg.relative_path = aether_local_path
    project.root_object.package_references << aether_pkg
    puts "added AetherEngine local package reference (#{aether_local_path})"
  end
  unless target.package_product_dependencies.any? { |d| d.product_name == 'AetherEngine' }
    dep = project.new(Xcodeproj::Project::Object::XCSwiftPackageProductDependency)
    dep.package = aether_pkg
    dep.product_name = 'AetherEngine'
    target.package_product_dependencies << dep
    bf = project.new(Xcodeproj::Project::Object::PBXBuildFile)
    bf.product_ref = dep
    target.frameworks_build_phase.files << bf
    puts 'linked AetherEngine product'
  end
else
  # The engine URL and revision live in the traits package's manifest.
  manifest = File.read(File.join(project_dir, 'AetherEngineTraits', 'Package.swift'))
  unless manifest.include?(aether_remote_url) && manifest.include?(aether_revision)
    abort "macos/AetherEngineTraits/Package.swift is not pinned to #{aether_remote_url} #{aether_revision}"
  end
end

# --- libass (standalone, for host-side ASS subtitle rendering) ---
libass_url = 'https://github.com/mpvkit/libass-build'
libass_pkg = project.root_object.package_references.find do |p|
  p.respond_to?(:repositoryURL) && p.repositoryURL == libass_url
end
unless libass_pkg
  libass_pkg = project.new(Xcodeproj::Project::Object::XCRemoteSwiftPackageReference)
  libass_pkg.repositoryURL = libass_url
  libass_pkg.requirement = { 'kind' => 'exactVersion', 'version' => '0.17.5' }
  project.root_object.package_references << libass_pkg
  puts 'added libass package reference'
end

unless target.package_product_dependencies.any? { |d| d.product_name == 'libass' }
  dep = project.new(Xcodeproj::Project::Object::XCSwiftPackageProductDependency)
  dep.package = libass_pkg
  dep.product_name = 'libass'
  target.package_product_dependencies << dep
  bf = project.new(Xcodeproj::Project::Object::PBXBuildFile)
  bf.product_ref = dep
  target.frameworks_build_phase.files << bf
  puts 'linked libass product'
end

# --- AetherEngine optional components ---
# The engine's object audio (TrueHD Atmos and DTS:X heights) and its Dolby
# Vision Profile 7 FEL route compile only with their package traits. Xcode 26
# ignores a traits list on the .pbxproj package reference, so the traits are
# set in a local package, macos/AetherEngineTraits, that depends on the same
# engine revision. Linking it makes SwiftPM build the engine with them.
traits_pkg = project.root_object.package_references.find do |p|
  p.is_a?(Xcodeproj::Project::Object::XCLocalSwiftPackageReference) &&
    p.relative_path.to_s == 'AetherEngineTraits'
end
if use_local_aether
  # The sibling checkout is linked directly; this package would add a second
  # path to the engine.
  if traits_pkg
    target.package_product_dependencies.dup.each do |d|
      next unless d.package&.uuid == traits_pkg.uuid
      d.referrers.grep(Xcodeproj::Project::Object::PBXBuildFile).each(&:remove_from_project)
      target.package_product_dependencies.delete(d)
      d.remove_from_project
    end
    project.root_object.package_references.delete(traits_pkg)
    traits_pkg.remove_from_project
    puts 'removed AetherEngineTraits package reference (AETHER_LOCAL=1)'
  end
elsif !traits_pkg
  traits_pkg = project.new(Xcodeproj::Project::Object::XCLocalSwiftPackageReference)
  traits_pkg.relative_path = 'AetherEngineTraits'
  project.root_object.package_references << traits_pkg
  puts 'added AetherEngineTraits package reference'
end

if !use_local_aether &&
   target.package_product_dependencies.none? { |d| d.product_name == 'AetherEngineTraits' }
  dep = project.new(Xcodeproj::Project::Object::XCSwiftPackageProductDependency)
  dep.package = traits_pkg
  dep.product_name = 'AetherEngineTraits'
  target.package_product_dependencies << dep
  bf = project.new(Xcodeproj::Project::Object::PBXBuildFile)
  bf.product_ref = dep
  target.frameworks_build_phase.files << bf
  puts 'linked AetherEngineTraits product'
end

# AetherEngine declares macOS 15 as its floor and SPM enforces it.
target.build_configurations.each do |config|
  config.build_settings['MACOSX_DEPLOYMENT_TARGET'] = '15.0'
end

project.build_configurations.each do |config|
  config.build_settings['MACOSX_DEPLOYMENT_TARGET'] = '15.0'
end

project.save
puts 'saved project'

