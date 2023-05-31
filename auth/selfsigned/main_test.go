package main

import (
	"github.com/nuts-foundation/go-did/did"
	"github.com/nuts-foundation/nuts-go-e2e-test/apps"
	"github.com/nuts-foundation/nuts-go-e2e-test/browser"
	didmanAPI "github.com/nuts-foundation/nuts-node/didman/api/v1"
	vcrAPI "github.com/nuts-foundation/nuts-node/vcr/api/vcr/v2"
	didAPI "github.com/nuts-foundation/nuts-node/vdr/api/v1"
	"github.com/rs/zerolog"
	"github.com/rs/zerolog/log"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
	"os"
	"testing"
	"time"
)

func Test_LoginWithSelfSignedMeans(t *testing.T) {
	const nodeURL = "http://localhost:1323"
	const purposeOfUse = "zorgtoepassing"
	log.Logger = log.Output(zerolog.ConsoleWriter{Out: os.Stderr})
	zerolog.SetGlobalLevel(zerolog.InfoLevel)

	ctx, cancel := browser.NewChrome(os.Getenv("SHOW_BROWSER") != "true")
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
	err = registerCompoundService(organization.ID, purposeOfUse)
	require.NoError(t, err)
	err = issueOrganizationCredential(organization)
	require.NoError(t, err)

	selfSigned := apps.SelfSigned{
		URL:     nodeURL,
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
	require.Equal(t, "The identificatie is voltooid. MAKE IT FAIL", acceptedText)

	// Check resulting VP
	status, presentation, err := selfSigned.GetSessionStatus(session.ID)
	require.NoError(t, err)
	require.Equal(t, "completed", status)
	require.Equal(t, "NutsSelfSignedPresentation", presentation.Type[1].String())
	require.Equal(t, organization.ID.String(), presentation.VerifiableCredential[0].Issuer.String())
	vpData, _ := presentation.MarshalJSON()
	log.Info().Msgf("VP: %s", string(vpData))

	// Now request an access token
	accessToken, err := selfSigned.RequestAccessToken(organization.ID.String(), purposeOfUse, presentation)
	require.NoError(t, err)
	assert.Equal(t, "zorgtoepassing", *accessToken.Service)
	assert.Equal(t, "J", *accessToken.Initials)
	assert.Equal(t, "Doe", *accessToken.FamilyName)
	assert.Equal(t, "Soulpeeker", *accessToken.UserRole)
	assert.Equal(t, "jdoe@example.com", *accessToken.Username)
	assert.Equal(t, "low", string(*accessToken.AssuranceLevel))

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

func registerCompoundService(id did.DID, compoundServiceType string) error {
	client := didmanAPI.HTTPClient{ClientConfig: apps.NodeClientConfig}
	_, err := client.AddCompoundService(id.String(), compoundServiceType, map[string]string{
		"oauth": apps.NodeClientConfig.Address + "/n2n/auth/v1/accesstoken",
	})
	return err
}

func createDID() (*did.Document, error) {
	didClient := didAPI.HTTPClient{ClientConfig: apps.NodeClientConfig}
	return didClient.Create(didAPI.DIDCreateRequest{})
}
