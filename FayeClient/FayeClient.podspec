Pod::Spec.new do |s|
  s.name         = "FayeClient"
  s.version      = "3.0"
  s.summary      = "Objective-C client library for the Faye Pub-Sub messaging server."
  s.homepage     = "https://github.com/tyrone-sudeium/FayeObjC"
  s.license      = {
    :type => 'MIT',
    :text => <<-LTEXT
                Copyright (c) 2011 Paul Crawford
                Copyright (c) 2013 Tyrone Trevorrow

                Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the 'Software'), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

                The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

                THE SOFTWARE IS PROVIDED 'AS IS', WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
                LTEXT
  }
  s.authors      = { "Tyrone Trevorrow" => "tyrone@sudeium.com", "Paul Crawford" => "pcrawfor@gmail.com" }
  s.source       = { :git => "https://github.com/tyrone-sudeium/FayeObjC.git", :branch => '3.0' }
  s.ios.deployment_target = '5.0'
  s.osx.deployment_target = '10.7'
  s.source_files = 'FayeClient/**/*.{h,m}'
  s.framework = 'CFNetwork'
  s.requires_arc = true
end
