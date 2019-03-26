#
# Be sure to run `pod lib lint Succulent.podspec' to ensure this is a
# valid spec before submitting.
#
# Any lines starting with a # are optional, but their use is encouraged
# To learn more about a Podspec see http://guides.cocoapods.org/syntax/podspec.html
#

Pod::Spec.new do |s|
  s.name             = 'Succulent'
  s.version          = '0.5.0'
  s.summary          = 'Succulent allows you to record and replay API responses to speed up and isolate
  your unit and UI tests.'

# This description is used to generate tags and improve search results.
#   * Think: What does it do? Why did you write it? What is the focus?
#   * Try to keep it short, snappy and to the point.
#   * Write the description between the DESC delimiters below.
#   * Finally, don't worry about the indent, CocoaPods strips it!

  s.description      = <<-DESC
A common problem is that an API is often developed in
tandem with the client. Succulent is designed specifically to remove the effort
in maintaining a specially built mock API by allowing you to record the current
API and replay it back in unit and UI tests. This allows you to quickly update
the tests when the API changes throughout your development cycle.
                       DESC

  s.homepage         = 'https://github.com/cactuslab/Succulent'
  # s.screenshots     = 'www.example.com/screenshots_1', 'www.example.com/screenshots_2'
  s.license          = { :type => 'MIT', :file => 'LICENSE' }
  s.author           = { 'Karl von Randow' => 'karl@cactuslab.com', 'Thomas Carey' => 'tom@cactuslab.com' }
  s.source           = { :git => 'https://github.com/cactuslab/Succulent.git', :tag => s.version.to_s }
  # s.social_media_url = 'https://twitter.com/<TWITTER_USERNAME>'

  s.ios.deployment_target = '8.0'

  s.source_files = 'Succulent/Classes/**/*.{m,h,swift}'
  s.swift_version = '5.0'
  s.dependency 'Embassy', '~> 4.0.8'
end
