package main

import (
	"github.com/nuts-foundation/go-did/did"
	"github.com/nuts-foundation/nuts-go-e2e-test/apps"
	"github.com/nuts-foundation/nuts-go-e2e-test/browser"
	vcrAPI "github.com/nuts-foundation/nuts-node/vcr/api/v2"
	didAPI "github.com/nuts-foundation/nuts-node/vdr/api/v1"
	"github.com/rs/zerolog"
	"github.com/rs/zerolog/log"
	"github.com/stretchr/testify/require"
	"os"
	"testing"
	"time"
)

func Test_LoginWithSelfSignedMeans(t *testing.T) {
	log.Logger = log.Output(zerolog.ConsoleWriter{Out: os.Stderr})
	zerolog.SetGlobalLevel(zerolog.InfoLevel)

	ctx, cancel := browser.NewChrome(false)
	defer func() {
		if t.Failed() {
			duration := 5 * time.Second
			log.Info().Msgf("Test failed, keeping browser open for %s", duration)
			time.Sleep(duration)
		}
		cancel()
	}()

	organization, err := createDID()
	require.NoError(t, err)
	err = issueOrganizationCredential(organization)
	require.NoError(t, err)

	selfSigned := apps.SelfSigned{
		URL:     "http://localhost:1323",
		Context: ctx,
	}
	roleName := "Soulpeeker"
	employeeInfo := apps.EmployeeInfo{
		Identifier: "jdoe@example.com",
		Initials:   "J",
		FamilyName: "Doe",
		RoleName:   &roleName,
	}
	// Start a self-signed session
	session, err := selfSigned.Start(organization.ID.String(), employeeInfo)
	require.NoError(t, err)
	require.Equal(t, employeeInfo.Identifier, session.EmployeeIdentifier)
	require.Equal(t, employeeInfo.Initials+" "+employeeInfo.FamilyName, session.EmployeeName)
	require.Equal(t, *employeeInfo.RoleName, session.EmployeeRole)

	// Accept
	acceptedText, err := selfSigned.Accept()
	require.NoError(t, err)
	require.Equal(t, "The identificatie is voltooid.", acceptedText)

	// Check resulting VP
	status, presentation, err := selfSigned.GetSessionStatus(session.ID)
	require.NoError(t, err)
	require.Equal(t, "completed", status)
	require.Equal(t, "NutsSelfSignedPresentation", presentation.Type[1].String())
	require.Equal(t, organization.ID.String(), presentation.VerifiableCredential[0].Issuer.String())
	vpData, _ := presentation.MarshalJSON()
	log.Info().Msgf("VP: %s", string(vpData))

	if os.Getenv("KEEP_BROWSER_OPEN") == "true" {
		timeout := time.Minute
		log.Info().Msgf("Keeping browser open for %s", timeout)
		time.Sleep(timeout)
	}
}

func issueOrganizationCredential(organization *did.Document) error {
	vcrClient := vcrAPI.HTTPClient{ClientConfig: apps.NodeClientConfig}
	visibility := vcrAPI.Public
	_, err := vcrClient.IssueVC(vcrAPI.IssueVCRequest{
		Type:   "NutsOrganizationCredential",
		Issuer: organization.ID.String(),
		CredentialSubject: map[string]interface{}{
			"id": organization.ID.String(),
			"organization": map[string]interface{}{
				"name": "Test organization",
				"city": "Testland",
			},
		},
		Visibility: &visibility,
	})
	return err
}

func createDID() (*did.Document, error) {
	didClient := didAPI.HTTPClient{ClientConfig: apps.NodeClientConfig}
	return didClient.Create(didAPI.DIDCreateRequest{})
}
