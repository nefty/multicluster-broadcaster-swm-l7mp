package main

import (
	"encoding/json"
	"fmt"
	"net/http"
	"os"

	whepclient "github.com/elixir-webrtc/whep-client"
	"github.com/pion/webrtc/v4"
)

type PcConfig struct {
	IceServers         []map[string]string
	IceTransportPolicy webrtc.ICETransportPolicy
}

func main() {
	url := os.Args[1]

	pcConfig := PcConfig{}

	resp, err := http.Get(url + "/api/pc-config")

	if err != nil {
		panic("Couldn't get peer connection config")
	}

	json.NewDecoder(resp.Body).Decode(&pcConfig)
	if err != nil {
		panic("Couldn't read response body")
	}

	pionPcConfig := webrtc.Configuration{}

	for i := 0; i < len(pcConfig.IceServers); i++ {
		iceServer := pcConfig.IceServers[i]
		pionIceServer := webrtc.ICEServer{}
		pionIceServer.URLs = []string{iceServer["urls"]}
		pionIceServer.Username = iceServer["username"]
		pionIceServer.Credential = iceServer["credential"]
		pionIceServer.CredentialType = webrtc.ICECredentialTypePassword
		pionPcConfig.ICEServers = append(pionPcConfig.ICEServers, pionIceServer)
	}

	pionPcConfig.ICETransportPolicy = pcConfig.IceTransportPolicy

	client, err := whepclient.New(url, pionPcConfig)
	if err != nil {
		panic(err)
	}

	client.Pc.OnICEConnectionStateChange(func(connectionState webrtc.ICEConnectionState) {
		fmt.Printf("Connection State has changed %s \n", connectionState.String())
	})

	client.Pc.OnTrack(func(track *webrtc.TrackRemote, receiver *webrtc.RTPReceiver) {
		fmt.Printf("New track: %s\n", track.Codec().MimeType)
		for {
			// do we need to call this if we ignore read packets anyway?
			_, _, err := track.ReadRTP()
			if err != nil {
				panic(err)
			}
		}
	})

	client.Connect()

	// block forever
	select {}
}
