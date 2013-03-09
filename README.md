FayeObjC Client 3.0
===

As of 3.0 I consider this fork to be too divergent from the original [FayeObjC](https://github.com/pcrawfor/FayeObjC) to have any hope of reconciling the changes back in.  So please consider this project a distinct fork separately maintained from the original.  Some of the features I added in my fork of 2.0:

# Added in 2.0

### Multiple Channels
This allows you to connect and assign handlers to more than one channel per connection.

### Block-based Handlers
As well as the typical delegation pattern, it's also possible to define a handler block for a received message.  These can be assigned when you add a subscription.

### Wildcard Channels
Supports listening to wildcard channels.  For example:

        /chat/1/users/*

This will listen to all sub-channels on `/chat/1/users`, such as `/chat/1/users/1` or `/chat/1/users/4`.

### Debug Logging
When you set the debug property to true on a FayeClient, all messages to-and-from the Faye server are written out (with a timestamp) to:

        /path/to/application/Library/Caches/faye.log

If the received message is valid JSON, it'll even pretty-print it for you!

# To Do for 3.0

### Cocoapods Support [done]
Remove all third-party dependencies from the base repository.  Create a podspec for FayeObjC and specify all dependencies there.  Add dependencies as submodules and update example projects to link to the dependencies and FayeClient using project linking.

### Long-polling Support [done?]
As well as websockets, the client should use long-polling if the connection URL is `http://` or `https://`.  Note that this behaviour differs from the Faye JavaScript client which - in my opinion - is really bizarre.

### Multiple Server Support [done]
A single `FayeClient` instance should be able to accept multiple server addresses, so in the event of a connection error to one, it can fall back on to another (if available).  The order of precedence is the order in which you add them to the Faye Client.

It will also keep track of how many connection errors have occurred on each registered server, and sort by that first.

### Better Support for Extensions
As well as the traditional method of just sending up an `NSDictionary` with every outgoing message, it'll also be possible to assign extensions per-server and per-channel and per-message.  The extension dictionary will be merged at the time messages are sent, prioritising keys in message, then channel, then server.  If you need even more fine-grained control than this, there's a special delegate you can implement that can override every single message sent and received from the server and allow the delegate to change the data as needed before being processed by the Faye Client or Faye Server.

### Better Support tor Edge Cases
The current client doesn't handle strange user behaviour like sending a `- connect` more than once very gracefully.  Hopefully with the help of some contributors (hint, hint) I can iron out a lot of these quirks.

### Modernise Everything
Use the new Objective-C literals and subscripting more pervasively.

# Working With the Library
This section will be written when 3.0 is closer to finalisation.

### Example Project:

Included in the repository is a sample XCode project for Mac that provides a simple client application for interacting with Faye servers.  Try it out and have a look at the code for an illustration on the usage of the library.

The fayeMac sample project allows you to test out any Faye server.

# Credits

## Faye
Faye is a simple JSON based Pub-Sub server which has support for node.js and Ruby (using Rack).

Check out the Faye project here:

* [http://faye.jcoglan.com](http://faye.jcoglan.com)

## SocketRocket
SocketRocket is a fast, RFC 6455 conforming WebSocket client library from the geniuses over at Square.

* [https://github.com/square/SocketRocket](https://github.com/square/SocketRocket)

## FayeObjC 1.0/2.0
The original FayeObjC client.

* [https://github.com/pcrawfor/FayeObjC](https://github.com/pcrawfor/FayeObjC)


## License

(The MIT License)

Copyright (c) 2011 Paul Crawford  
Copyright (c) 2013 Tyrone Trevorrow

Permission is hereby granted, free of charge, to any person obtaining
a copy of this software and associated documentation files (the
'Software'), to deal in the Software without restriction, including
without limitation the rights to use, copy, modify, merge, publish,
distribute, sublicense, and/or sell copies of the Software, and to
permit persons to whom the Software is furnished to do so, subject to
the following conditions:

The above copyright notice and this permission notice shall be
included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED 'AS IS', WITHOUT WARRANTY OF ANY KIND,
EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.
IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY
CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT,
TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE
SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
