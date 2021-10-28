package main

import "net/http"
import "os"

func main() {
    if len(os.Args) < 2 {
        os.Exit(1)
    }
    url := os.Args[1]

    r, err := http.NewRequest("GET", url, nil)
    if err != nil {
        os.Exit(1)
    }
    p, err := http.ProxyFromEnvironment(r)
    if err != nil {
        os.Exit(1)
    }
    if p == nil {
		// No proxy returned, we need to clear the proxies
        os.Exit(0)
    }
    os.Exit(1)
}
