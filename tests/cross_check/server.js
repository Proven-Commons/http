// A Node HTTP server with its default, strict parser (llhttp). It prints
// its port first. It answers 200 to each request whose head it reads,
// with an X-Body field that says how many body octets it read and how
// the body ended:
// - "N end": the body ended where Node's framing says it ends;
// - "N eof": the client closed its side before that;
// - "N error CODE": llhttp found an error in the body.
// It answers 400 when llhttp refuses the head itself. Node hands a
// CONNECT request to the 'connect' event and reads what follows as a
// tunnel, not a body, so that answer says "tunnel".
//
// llhttp checks Transfer-Encoding just after Node has passed the request
// on. When the last coding is not chunked, it then stops with
// HPE_INVALID_TRANSFER_ENCODING. That is a refusal of the head, so it
// gets 400 too.
const http = require('http');

// The sockets whose request head was read and not yet answered, each
// with a function that gives the body octets read so far.
const reading = new Map();

function write(socket, status, xbody) {
  if (!socket.writable) return;
  socket.end(`HTTP/1.1 ${status}\r\nX-Body: ${xbody}\r\nContent-Length: 0\r\n` +
             'Connection: close\r\n\r\n');
}

const srv = http.createServer((req, res) => {
  let n = 0;
  reading.set(req.socket, () => n);
  req.on('data', (c) => { n += c.length; });
  req.on('end', () => {
    reading.delete(req.socket);
    res.writeHead(200, { Connection: 'close', 'X-Body': `${n} end`, 'Content-Length': 0 });
    res.end();
  });
});
srv.on('connect', (req, socket) => {
  write(socket, '200 OK', 'tunnel');
});
srv.on('clientError', (err, socket) => {
  const read = reading.get(socket);
  reading.delete(socket);
  if (read && err.code !== 'HPE_INVALID_TRANSFER_ENCODING') {
    const how = err.code === 'HPE_INVALID_EOF_STATE' ? 'eof' : `error ${err.code}`;
    write(socket, '200 OK', `${read()} ${how}`);
  } else {
    write(socket, '400 Bad Request', `none ${err.code}`);
  }
  socket.destroySoon();
});
srv.listen(0, '127.0.0.1', () => console.log(srv.address().port));
