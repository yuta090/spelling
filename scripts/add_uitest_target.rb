#!/usr/bin/env ruby
# frozen_string_literal: true
#
# SpellingTrainerUITests（XCUITest バンドル）ターゲットを Xcode プロジェクトに追加する。
# 手編集の pbxproj 破損を避けるため xcodeproj gem を使う。冪等（既存ならスキップ）。
#   ruby scripts/add_uitest_target.rb
require 'xcodeproj'

PROJECT = 'SpellingTrainer.xcodeproj'
APP_TARGET = 'SpellingTrainer'
TEST_TARGET = 'SpellingTrainerUITests'
TEST_BUNDLE_ID = 'com.yuta090.SpellingTrainerUITests'

project = Xcodeproj::Project.open(PROJECT)
app = project.targets.find { |t| t.name == APP_TARGET }
raise "app target #{APP_TARGET} not found" unless app

if project.targets.any? { |t| t.name == TEST_TARGET }
  puts "#{TEST_TARGET} already exists; nothing to do."
  exit 0
end

deployment = app.deployment_target || '17.0'
swift_version = app.build_configurations.map { |c| c.build_settings['SWIFT_VERSION'] }.compact.first || '5.0'

test_target = project.new_target(:ui_test_bundle, TEST_TARGET, :ios, deployment)

# テストソースを追加。
group = project.main_group.new_group(TEST_TARGET, TEST_TARGET)
file_ref = group.new_reference('PaywallE2ETests.swift')
test_target.add_file_references([file_ref])

# テスト対象アプリへの依存。
test_target.add_dependency(app)

test_target.build_configurations.each do |config|
  s = config.build_settings
  s['TEST_TARGET_NAME'] = APP_TARGET
  s['PRODUCT_BUNDLE_IDENTIFIER'] = TEST_BUNDLE_ID
  s['PRODUCT_NAME'] = '$(TARGET_NAME)'
  s['GENERATE_INFOPLIST_FILE'] = 'YES'
  s['SWIFT_VERSION'] = swift_version
  s['IPHONEOS_DEPLOYMENT_TARGET'] = deployment
  s['TARGETED_DEVICE_FAMILY'] = '1,2'
  s['CODE_SIGNING_ALLOWED'] = 'NO'
  s['SWIFT_EMIT_LOC_STRINGS'] = 'NO'
  s['MARKETING_VERSION'] = '1.0'
  s['CURRENT_PROJECT_VERSION'] = '1'
end

project.save

# 共有スキームの TestAction にテスタブルを追加。
scheme_dir = Xcodeproj::XCScheme.shared_data_dir(PROJECT)
scheme_path = File.join(scheme_dir.to_s, "#{APP_TARGET}.xcscheme")
scheme = Xcodeproj::XCScheme.new(scheme_path)
scheme.add_test_target(test_target)
scheme.save!

puts "Added #{TEST_TARGET} target, source, dependency, and scheme testable."
