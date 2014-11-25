package main

import (
	"flag"
	"fmt"
	"log"
	"net/http"
	"net/url"
	"os"
	"runtime"
	"strings"

	"bitbucket.org/ww/goautoneg"
	"github.com/garyburd/redigo/redis"
)

var redisAddr string
var addr string

func main() {
	flagEnvStringVar(&redisAddr, "redis", "REDISSE_REDIS", "redis://localhost:6379/", "Redis server URL")
	flagEnvStringVar(&addr, "listen", "REDISSE_PORT", "localhost:8080", "Redisse binding address")
	flag.Parse()
	parseRedisAddr()
	parseAddr()
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
	values, err := url.ParseQuery(r.URL.RawQuery)
	channels := make([]string, len(values))
	if err != nil {
		return channels
	}
	i := 0
	for channel := range values {
		channels[i] = channel
		i++
	}
	return channels
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

// CLI

func flagEnvStringVar(p *string, name string, envVar string, defaultVal string, usage string) flag.Getter {
	value := os.Getenv(envVar)
	if value == "" {
		value = defaultVal
	}
	*p = value
	s := flag.Getter(&stringEnvValue{p, envVar, defaultVal})
	flag.Var(s, name, usage) //envVar+" or "+defaultVal)
	return s
}

func parseRedisAddr() {
	u, err := url.Parse(redisAddr)
	if err != nil {
		log.Fatal(err)
	}
	if u.Scheme != "" && u.Scheme != "redis" {
		log.Fatalf("redis URL expected, got: %v", u)
	}
	redisAddr = u.Host
}

func parseAddr() {
	if addr == "" {
		addr = "localhost:8080"
	} else if !strings.Contains(addr, ":") {
		addr = "localhost:" + addr
	}
}

type stringEnvValue struct {
	p          *string
	envVar     string
	defaultVal string
}

func (s *stringEnvValue) Set(value string) error {
	*s.p = value
	return nil
}

func (s *stringEnvValue) Get() interface{} {
	log.Println(s.envVar, "Get()")
	return *s.p
}

func (s *stringEnvValue) String() string {
	return fmt.Sprintf("%s or %q", s.envVar, *s.p)
}
