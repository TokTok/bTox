// A Go version WebSocket to TCP socket proxy
//
// This is a heavily modifier version of this file:
//   https://github.com/novnc/websockify-other/blob/master/golang/websockify.go
//
// Changes include:
// - Fix infinite loop on error.
// - Use base64 encoding for all communications.
// - Proper logging.
// - Proper error handling in general.
//
// Copyright 2022 The TokTok team.
// Copyright 2021 Michael.liu.
// See LICENSE for licensing conditions.

package main

import (
	"encoding/base64"
	"encoding/hex"
	"flag"
	"log"
	"net"
	"net/http"

	"github.com/gorilla/websocket"
)

var (
	source_addr = flag.String("l", "127.0.0.1:8080", "http service address")
	target_addr = flag.String("t", "127.0.0.1:5900", "tcp service address")
)

var upgrader = websocket.Upgrader{
	ReadBufferSize:  1024,
	WriteBufferSize: 1024,
	CheckOrigin: func(r *http.Request) bool {
		return true
	},
}

func forwardTcp(wsconn *websocket.Conn, conn net.Conn) {
	var tcpbuffer [2048]byte
	defer wsconn.Close()
	defer conn.Close()
	for {
		n, err := conn.Read(tcpbuffer[0:])
		if err != nil {
			log.Println("TCP READ :", err)
			break
		}
		encoded := base64.StdEncoding.EncodeToString(tcpbuffer[0:n])
		if err := wsconn.WriteMessage(websocket.BinaryMessage, []byte(encoded)); err != nil {
			log.Println("WS WRITE :", err)
			break
		}
		log.Println("WS WRITE :", n)
	}
}

func forwardWeb(wsconn *websocket.Conn, conn net.Conn) {
	defer wsconn.Close()
	defer conn.Close()
	for {
		_, buffer, err := wsconn.ReadMessage()
		if err != nil {
			log.Println("WS READ  :", err)
			break
		}
		decoded, err := base64.StdEncoding.DecodeString(string(buffer))
		if err != nil {
			log.Println("WS READ  :", err)
			break
		}
		log.Println("WS READ  :", len(decoded), hex.EncodeToString(decoded))

		m, err := conn.Write(decoded)
		if err != nil {
			log.Println("TCP WRITE:", err)
			break
		}
		log.Println("TCP WRITE:", m)
	}
}

func serveWs(w http.ResponseWriter, r *http.Request) {
	ws, err := upgrader.Upgrade(w, r, nil)
	if err != nil {
		log.Println("upgrade:", err)
		return
	}
	vnc, err := net.Dial("tcp", *target_addr)
	if err != nil {
		log.Println("dial:", err)
		return
	}
	go forwardTcp(ws, vnc)
	go forwardWeb(ws, vnc)

}

func main() {
	flag.Parse()
	log.Println("Starting up websockify endpoint")

	http.HandleFunc("/", func(w http.ResponseWriter, r *http.Request) {
		http.ServeFile(w, r, r.URL.Path[1:])
	})
	http.HandleFunc("/websockify", serveWs)
	log.Fatal(http.ListenAndServe(*source_addr, nil))
}
