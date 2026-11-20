// A Go net/http server. It prints its port first. It answers 200 to
// each request whose head it reads, with an X-Body field that says how
// many body octets it read and how the body ended:
//   - "N end": the body ended where Go's framing says it ends;
//   - "N eof": the client closed its side before that;
//   - "N error": Go found an error in the body.
//
// Go itself answers 400 when it refuses the head. Requests for
// "OPTIONS *" also come to this handler.
package main

import (
	"errors"
	"fmt"
	"io"
	"net"
	"net/http"
	"os"
)

func main() {
	ln, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		fmt.Fprintln(os.Stderr, err)
		os.Exit(1)
	}
	fmt.Println(ln.Addr().(*net.TCPAddr).Port)
	srv := &http.Server{
		DisableGeneralOptionsHandler: true,
		Handler: http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			b, err := io.ReadAll(r.Body)
			how := "end"
			if errors.Is(err, io.ErrUnexpectedEOF) {
				how = "eof"
			} else if err != nil {
				how = "error"
			}
			w.Header().Set("Connection", "close")
			w.Header().Set("X-Body", fmt.Sprintf("%d %s", len(b), how))
		}),
	}
	srv.Serve(ln)
}
