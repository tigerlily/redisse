package main

import (
	"flag"
	"fmt"
	"log"
	"net/http"
	"runtime"

	"bitbucket.org/ww/goautoneg"
	"github.com/garyburd/redigo/redis"
)

var redisAddr string

func main() {
	flag.StringVar(&redisAddr, "redis", ":6379", "Redis server URL")
	flag.Parse()
	fmt.Println(redisAddr)
	addr := flag.Arg(0)
	if addr == "" {
		addr = ":8082"
	}
	http.HandleFunc("/", response)
	log.Fatal(http.ListenAndServe(addr, nil))
}

const eventStreamMediaType = "text/event-stream"

func response(w http.ResponseWriter, r *http.Request) {
	fmt.Print("+")
	if !isAcceptable(r) {
		notAcceptable(w)
		return
	}
	s := startStream(w)
	subscribe(s, r)
	fmt.Print("-", runtime.NumGoroutine())
}

func isAcceptable(r *http.Request) bool {
	accept := goautoneg.Negotiate(r.Header.Get("Accept"),
		[]string{eventStreamMediaType})
	return accept == eventStreamMediaType
}

func notAcceptable(w http.ResponseWriter) {
	http.Error(w,
		"406 Not Acceptable\n"+
			"This resource can only be represented as "+
			eventStreamMediaType+".\n",
		http.StatusNotAcceptable)
}

func connectPubSub() (*redis.PubSubConn, error) {
	conn, err := redis.Dial("tcp", redisAddr)
	if err != nil {
		panic(fmt.Sprintf("Connection failed: %s", redisAddr))
	}
	return &redis.PubSubConn{Conn: conn}, err
}

func subscribe(s stream, r *http.Request) {
	pubsub, _ := connectPubSub()
	defer pubsub.Close()
	channels := channels(r)
	for message := range receiveUntil(pubsub, s.CloseNotify(), channels...) {
		s.streamSend(message)
	}
}

func receiveUntil(pubsub *redis.PubSubConn, stop <-chan bool, channels ...string) <-chan string {
	messages := make(chan string)
	go func() {
		defer close(messages)
		for {
			switch n := pubsub.Receive().(type) {
			case redis.Message:
				fmt.Printf("Message: %s %s\n", n.Channel, n.Data)
				messages <- string(n.Data)
			case redis.Subscription:
				if n.Kind == "unsubscribe" {
					// Unsubscribe is used to make Receive() return a value but
					// means we should stop the goroutine
					fmt.Println("Finishing goroutine", n)
					return
				}
			case error:
				fmt.Printf("error: %v\n", n)
				return
			default:
				fmt.Printf("?? %s\n", n)
			}
		}
	}()
	go func() {
		<-stop
		fmt.Println("Stopping by unsubscribing")
		pubsub.Unsubscribe("") // any value will do because it will unblock Receive()
	}()
	for _, channel := range channels {
		pubsub.Subscribe(channel)
	}
	return messages
}

func channels(r *http.Request) []string {
	return []string{"global", "other", "all"}
}

// HTTP stream

type streamer interface {
	http.ResponseWriter
	http.Flusher
	http.CloseNotifier
}

type stream struct {
	streamer
}

func startStream(w http.ResponseWriter) stream {
	s := stream{w.(streamer)}
	s.Header().Set("Content-Type", "text/event-stream")
	s.Header().Set("Cache-Control", "no-cache")
	s.WriteHeader(http.StatusOK)
	s.Flush()
	return s
}

func (s stream) streamSend(str string) {
	fmt.Fprint(s, str)
	s.Flush()
}
