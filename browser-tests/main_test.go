package main

import (
	"context"
	"github.com/nuts-foundation/nuts-go-e2e-test/browser"
	"github.com/rs/zerolog"
	"github.com/rs/zerolog/log"
	"github.com/stretchr/testify/assert"
	"os"
	"runtime"
	"testing"
	"time"
)
import "github.com/nuts-foundation/nuts-go-e2e-test/apps"

func Test_eOverdracht(t *testing.T) {
	log.Logger = log.Output(zerolog.ConsoleWriter{Out: os.Stderr})
	zerolog.SetGlobalLevel(zerolog.InfoLevel)

	ctx, cancel := browser.NewChrome(false)
	defer cancel()

	hapiURL := "http://localhost:8080"
	nodeURL := "http://localhost:1323"
	registryAdminURL := "http://localhost:1303"
	ehrURL := "http://localhost:1304"

	hapi := apps.HAPI{URL: hapiURL}
	ehr := apps.DemoEHR{
		URL:     ehrURL,
		Context: ctx,
		HAPI:    hapi,
	}

	ziekenhuis := apps.Customer{
		CareOrganization: apps.CareOrganization{
			Name: "Ziekenhuis de Breuk",
			City: "Breukelen",
		},
		InternalID: 1,
		Domain:     "breukelen.nl",
	}
	wijkverpleging := apps.Customer{
		CareOrganization: apps.CareOrganization{
			Name: "Wijkverpleging de Wijk",
			City: "Ons Dorp",
		},
		InternalID: 2,
		Domain:     "dewijk.nl",
	}
	patient := apps.Patient{
		SocialSecurityNumber: "1234567890",
		Firstname:            "Titus",
		Lastname:             "Tester",
		Gender:               "male",
		Zipcode:              "9999AA",
		DateOfBirth:          "1974-05-03",
		Email:                "titus@tester.io",
	}
	transferRequest := apps.TransferRequest{
		ReceiverOrganizationName: wijkverpleging.Name,
		Date:                     "2025-05-03",
		Problem:                  "Gebroken pols",
		Intervention:             "Gips",
	}

	t.Run("Set up vendor and customers", func(t *testing.T) {
		registryAdmin := apps.RegistryAdmin{
			URL:     registryAdminURL,
			Context: ctx,
		}
		NoError(t, registryAdmin.Login())
		if registryAdmin.IsSetUp() {
			log.Info().Msg("Registry admin is already set up, skipping")
			t.SkipNow()
		}

		// Register vendor
		NoError(t, registryAdmin.RegisterVendor(apps.Vendor{
			Name:             "CareSoft",
			Email:            "info@caresoft.nl",
			Website:          "https://software.care",
			NutsNodeEndpoint: "grpc://localhost:5555",
		}))

		// Register endpoints
		endpoints := []apps.Endpoint{
			{Type: "eoverdracht-notification-receiver", URL: ehrURL + "/web/external/transfer/notify"},
			{Type: "eoverdracht-fhir", URL: ehrURL + "/fhir"},
			{Type: "oauth-request-accesstoken", URL: nodeURL + "/n2n/auth/v1/accesstoken"},
		}
		for _, endpoint := range endpoints {
			NoError(t, registryAdmin.RegisterEndpoint(endpoint))
		}

		// Register compound services
		services := []apps.Service{
			{
				Name: "eOverdracht-sender",
				Endpoints: map[string]string{
					"fhir":  "eoverdracht-fhir",
					"oauth": "oauth-request-accesstoken",
				},
			},
			{
				Name: "eOverdracht-receiver",
				Endpoints: map[string]string{
					"notification": "eoverdracht-notification-receiver",
					"oauth":        "oauth-request-accesstoken",
				},
			},
		}
		for _, service := range services {
			NoError(t, registryAdmin.RegisterService(service))
		}

		// Register & publish care organizations
		NoError(t, registryAdmin.RegisterCustomer(ziekenhuis))
		NoError(t, registryAdmin.PublishCustomer(1, "eOverdracht-sender"))

		NoError(t, registryAdmin.RegisterCustomer(wijkverpleging))
		NoError(t, registryAdmin.PublishCustomer(2, "eOverdracht-receiver"))
	})
	t.Run("Create patient", func(t *testing.T) {
		// Wait for HAPI to become ready, because the patient will be created as FHIR resource as well,
		// and the care organizations will be created as tenants in HAPI server when they log in.
		hapiCtx, cancelFn := context.WithDeadline(ctx, time.Now().Add(time.Minute))
		defer cancelFn()
		NoError(t, hapi.WaitForReady(hapiCtx))

		// Log in to EHR for ziekenhuis, create patient, transfer to wijkverpleging
		NoError(t, ehr.Login(ziekenhuis))
		NoError(t, ehr.RegisterPatient(patient))
	})
	t.Run("Transfer patient to wijkverpleging", func(t *testing.T) {
		NoError(t, ehr.CreateAndAssignPatientTransfer(patient, transferRequest))
	})
	t.Run("View received patient transfer", func(t *testing.T) {
		// Now log in to HAPI for wijkverpleging, and check that the patient is transferred
		NoError(t, ehr.Logout())
		NoError(t, ehr.Login(wijkverpleging))
		NoError(t, ehr.ViewTransferRequestInInbox(t, ziekenhuis.CareOrganization, patient))
		NoError(t, ehr.ViewTransferRequestDetails(t, ziekenhuis.CareOrganization, patient, transferRequest))
	})

	if os.Getenv("KEEP_BROWSER_OPEN") == "true" {
		timeout := time.Minute
		log.Info().Msgf("Keeping browser open for %s", timeout)
		time.Sleep(timeout)
	}
}

func NoError(t *testing.T, err error) {
	if !assert.NoError(t, err) {
		runtime.Goexit()
	}
}
