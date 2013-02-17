var http = require('http'),
    faye = require('faye');

var bayeux = new faye.NodeAdapter({
  mount:    '/faye',
  timeout:  45
});

// Handle non-Bayeux requests
var server = http.createServer(function(request, response) {
  response.writeHead(200, {'Content-Type': 'text/plain'});
  response.write('Non-Bayeux request');
  response.end();
});

bayeux.attach(server);
server.listen(8000);

var cli = bayeux.getClient();
function sendDateLoop(cli) {
	setTimeout(function(){sendDateLoop(cli);}, (Math.floor(Math.random() * 5) + 2) * 1000);
	cli.publish("/testing", { 'date': new Date().toString() });
}

sendDateLoop(cli);



