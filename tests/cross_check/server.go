// A Go net/http server: it answers each request it reads with 200 and
// the number of body octets it read, and prints its port first.
package main

import (
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
	http.Serve(ln, http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		b, _ := io.ReadAll(r.Body)
		w.Header().Set("Connection", "close")
		fmt.Fprintf(w, "%d", len(b))
	}))
}
