package main

import (
	"fmt"
	"log"
	"net"
	"net/http"
	"runtime"

	"bitbucket.org/ww/goautoneg"
	"github.com/garyburd/redigo/redis"
)

func main() {
	http.HandleFunc("/", response)
	log.Fatal(http.ListenAndServe(":8082", nil))
}

const eventStreamMediaType = "text/event-stream"

type stream interface {
	http.ResponseWriter
	http.Flusher
	http.CloseNotifier
}

func response(w http.ResponseWriter, r *http.Request) {
	if !isAcceptable(r) {
		notAcceptable(w)
		return
	}
	s, ok := w.(stream)
	if !ok {
		http.Error(w, "Streaming unsupported", http.StatusInternalServerError)
		return
	}
	s.Header().Set("Content-Type", "text/event-stream")
	s.Header().Set("Cache-Control", "no-cache")
	s.Header().Set("Connection", "keep-alive")
	s.Header().Set("X-Accel-Buffering", "no")
	s.WriteHeader(http.StatusOK)
	s.Flush()
	subscribe(s, r)
	fmt.Printf("No of goroutines: %v\n", runtime.NumGoroutine())
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
	address := "localhost:6379"
	conn, err := redis.Dial("tcp", address)
	if err != nil {
		panic(fmt.Sprintf("Connection failed: %s", address))
	}
	return &redis.PubSubConn{conn}, err
}

func subscribe(s stream, r *http.Request) {
	//connectionClosed := s.CloseNotify()

	pubsub, _ := connectPubSub()
	defer func() {
		fmt.Printf("Closing PubSub connection\n")
		pubsub.Close()
	}()

	//messages, done := receive(pubsub, "global", "other")

	channels := []string{"global", "other"}
	for message := range receiveUntil(pubsub, s.CloseNotify(), channels...) {
		fmt.Fprintf(s, message)
		s.Flush()
	}

	//Loop:
	//	for {
	//		select {
	//		case message := <-messages:
	//			fmt.Fprintf(s, message)
	//			s.Flush()
	//		case <-connectionClosed:
	//			fmt.Printf("HTTP connection closed\n")
	//			fmt.Printf("Unsubscribing\n")
	//			pubsub.Unsubscribe()
	//			break Loop
	//		}
	//	}
	//	<-done
	fmt.Printf("Over\n")
}

func receiveUntil(pubsub *redis.PubSubConn, stop <-chan bool, channels ...string) <-chan string {
	messages := make(chan string)
	go func() {
		defer close(messages)
		for {
			fmt.Printf(".")
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
			fmt.Println("end of for loop")
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

func keepLooping(err net.Error, stop <-chan bool) bool {
	if err.Timeout() {
		fmt.Println("timeout")
		select {
		case <-stop:
			return false
		default:
		}
	}
	return true
}

//func receive(pubsub *redis.PubSubConn, channels ...string) (<-chan string, chan bool) {
//	messages := make(chan string)
//	done := make(chan bool)
//	go func() {
//		defer close(messages)
//		defer func() {
//			done <- true
//		}()
//		for {
//			switch n := pubsub.Receive().(type) {
//			case redis.Message:
//				fmt.Printf("Message: %s %s\n", n.Channel, n.Data)
//				messages <- string(n.Data)
//			case redis.Subscription:
//				fmt.Printf("%v\n", n)
//				if n.Count == 0 {
//					return
//				}
//			case error:
//				fmt.Printf("error: %v\n", n)
//				return
//			default:
//				fmt.Printf("?? %s\n", n)
//			}
//		}
//	}()
//	for _, channel := range channels {
//		pubsub.Subscribe(channel)
//	}
//	return messages, done
//}
