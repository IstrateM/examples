// Copyright 2019 Cisco Systems, Inc.
// SPDX-License-Identifier: Apache-2.0
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at:
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

package main

import (
	"flag"
	"fmt"
	"net"
	"os"
	"strconv"
	"strings"

	"github.com/danielvladco/k8s-vnet/pkg/nseconfig"
	"github.com/networkservicemesh/examples/examples/universal-cnf/vppagent/pkg/config"
	"github.com/networkservicemesh/examples/examples/universal-cnf/vppagent/pkg/vppagent"
	"github.com/networkservicemesh/networkservicemesh/controlplane/api/networkservice"
	"github.com/networkservicemesh/networkservicemesh/pkg/tools"
	"github.com/networkservicemesh/networkservicemesh/sdk/common"
	"github.com/networkservicemesh/networkservicemesh/sdk/endpoint"
	"github.com/sirupsen/logrus"
	"gopkg.in/yaml.v2"
)

const (
	defaultConfigPath   = "/etc/universal-cnf/config.yaml"
	defaultPluginModule = ""
)

// Flags holds the command line flags as supplied with the binary invocation
type Flags struct {
	ConfigPath string
	Verify     bool
}

type fnGetNseName func() string

// Process will parse the command line flags and init the structure members
func (mf *Flags) Process() {
	flag.StringVar(&mf.ConfigPath, "file", defaultConfigPath, " full path to the configuration file")
	flag.BoolVar(&mf.Verify, "verify", false, "only verify the configuration, don't run")
	flag.Parse()
}

type vL3CompositeEndpoint string

func (vL3ce vL3CompositeEndpoint) AddCompositeEndpoints(nsConfig *common.NSConfiguration, ucnfEndpoint *nseconfig.Endpoint) *[]networkservice.NetworkServiceServer {
	nsPodIp, ok := os.LookupEnv("NSE_POD_IP")
	if !ok {
		nsPodIp = "2.2.20.0" // needs to be set to make sense
	}
	ipamUseNsPodOctet := false
	nseUniqueOctet, ok := os.LookupEnv("NSE_IPAM_UNIQUE_OCTET")
	if !ok {
		ipamUseNsPodOctet = true
	}
	prefixPool := ""
	// Find the 3rd octet of the pod IP
	if nsConfig.IPAddress != "" {
		prefixPoolIP, _, err := net.ParseCIDR(nsConfig.IPAddress)
		if err != nil {
			logrus.Errorf("Failed to parse configured prefix pool IP")
			prefixPoolIP = net.ParseIP("1.1.0.0")
		}
		var ipamUniqueOctet int
		if ipamUseNsPodOctet {
			podIP := net.ParseIP(nsPodIp)
			if podIP == nil {
				logrus.Errorf("Failed to parse configured pod IP")
				ipamUniqueOctet = 0
			} else {
				ipamUniqueOctet = int(podIP.To4()[2])
			}
		} else {
			ipamUniqueOctet, _ = strconv.Atoi(nseUniqueOctet)
		}
		prefixPool = fmt.Sprintf("%d.%d.%d.%d/24",
			prefixPoolIP.To4()[0],
			prefixPoolIP.To4()[1],
			ipamUniqueOctet,
			0)
	}
	logrus.WithFields(logrus.Fields{
		"prefixPool":         prefixPool,
		"nsPodIP":            nsPodIp,
		"nsConfig.IPAddress": nsConfig.IPAddress,
	}).Infof("Creating vL3 IPAM endpoint")
	ipamEp := endpoint.NewIpamEndpoint(&common.NSConfiguration{
		IPAddress: prefixPool,
	})

	var nsRemoteIpList []string
	nsRemoteIpListStr, ok := os.LookupEnv("NSM_REMOTE_NS_IP_LIST")
	if ok {
		nsRemoteIpList = strings.Split(nsRemoteIpListStr, ",")
	}
	compositeEndpoints := []networkservice.NetworkServiceServer{
		ipamEp,
		newVL3ConnectComposite(nsConfig, prefixPool,
			&vppagent.UniversalCNFVPPAgentBackend{}, nsRemoteIpList, func() string {
				return ucnfEndpoint.NseName
			}),
	}

	return &compositeEndpoints
}

// exported the symbol named "CompositeEndpointPlugin"
var CompositeEndpointPlugin vL3CompositeEndpoint

func main() {
	// Capture signals to cleanup before exiting
	c := tools.NewOSSignalChannel()

	logrus.SetOutput(os.Stdout)
	logrus.SetLevel(logrus.TraceLevel)

	mainFlags := &Flags{}
	mainFlags.Process()

	cnfConfig := &nseconfig.Config{}
	f, err := os.Open(mainFlags.ConfigPath)
	if err != nil {
		logrus.Fatal(err)
	}
	err = nseconfig.NewConfig(yaml.NewDecoder(f), cnfConfig)
	if err != nil {
		logrus.Fatal(err)
	}

	configuration := common.FromEnv()

	backend := &vppagent.UniversalCNFVPPAgentBackend{}
	if err := backend.NewUniversalCNFBackend(); err != nil {
		logrus.Fatal(err)
	}

	pe := config.NewProcessEndpoints(backend, cnfConfig.Endpoints, configuration, CompositeEndpointPlugin)

	logrus.Infof("Starting endpoints")
	// defer pe.Cleanup()

	if err := pe.Process(); err != nil {
		logrus.Fatalf("Error processing the new endpoints: %v", err)
	}

	defer pe.Cleanup()
	<-c
}
