// A Node HTTP server with its default, strict parser (llhttp): it
// answers each request it reads with 200 and the number of body octets
// it read, and prints its port first. Node hands a CONNECT request to
// the 'connect' event, which answers 200 with no count.
const http = require('http');
const srv = http.createServer((req, res) => {
  let n = 0;
  req.on('data', (c) => { n += c.length; });
  req.on('end', () => {
    const body = String(n);
    res.writeHead(200, { Connection: 'close', 'Content-Length': body.length });
    res.end(body);
  });
});
srv.on('connect', (req, socket) => {
  socket.end('HTTP/1.1 200 OK\r\nContent-Length: 0\r\nConnection: close\r\n\r\n');
});
srv.listen(0, '127.0.0.1', () => console.log(srv.address().port));
