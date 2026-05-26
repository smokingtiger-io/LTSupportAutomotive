Pod::Spec.new do |s|
  s.name             = "LTSupportAutomotive"
  s.version          = "1.0"
  s.summary          = "LTSupportAutomotive is a library for writing apps that communicate with vehicles using OBD2 adapters."
  s.homepage         = "https://github.com/mickeyl/LTSupportAutomotive"
  s.license          = { :type => "MIT" }
  s.authors          = { "Dr. Michael Lauer" => "mickey@vanille.de" }
  s.source           = { :git => "https://github.com/mickeyl/LTSupportAutomotive.git", :tag => "1.0.0" }

  # Aligned with Package.swift (iOS 13). The library uses Swift Concurrency-
  # friendly APIs and modern CoreBluetooth methods that aren't backwards
  # compatible to iOS 9 anyway.
  s.platform     = :ios, "13.0"
  s.requires_arc = true

  s.source_files = ["LTSupportAutomotive/*.{h,m}"]
  s.resources = ['LTSupportAutomotive/**/*.{strings,lproj}']
  s.resource_bundle = { 'LTSupportAutomotive' => [ 'LTSupportAutomotive/**/*.lproj' ] }
  s.frameworks = 'Foundation', 'CoreBluetooth'
end

