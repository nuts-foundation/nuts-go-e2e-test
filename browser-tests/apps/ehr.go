package apps

import (
	"context"
	"fmt"
	"github.com/chromedp/chromedp"
	"github.com/stretchr/testify/assert"
	"testing"
	"time"
)

type DemoEHR struct {
	URL     string
	Context context.Context
	HAPI    HAPI
}

type Patient struct {
	SocialSecurityNumber string
	Firstname            string
	Lastname             string
	Gender               string
	Zipcode              string
	DateOfBirth          string
	Email                string
}

func (r DemoEHR) Login(customer Customer) error {
	//var selectOptions []*cdp.Node
	var authenticatedOrganizationName string
	var val string
	return chromedp.Run(r.Context,
		logInfo("Logging into Demo EHR for customer: %s", customer.Name),
		chromedp.Navigate(r.URL),
		// Wait for customer list to be populated
		chromedp.Value(`#customer_select > option[value='1']`, &val),
		// Select customer
		chromedp.SetValue("#customer_select", fmt.Sprintf("%d", customer.InternalID), chromedp.NodeVisible),
		//chromedp.ActionFunc(func(ctx context.Context) error {
		//	return r.HAPI.WaitForTenant(ctx, customer.InternalID)
		//}),
		chromedp.WaitEnabled("#password-button"),
		chromedp.Click("#password-button"),
		chromedp.SetValue("#password-input", "demo"),
		chromedp.Click("#login-button"),
		chromedp.WaitVisible("#patients-menu-link"),
		chromedp.Text("current-organization-name", &authenticatedOrganizationName),
		chromedp.ActionFunc(func(ctx context.Context) error {
			if customer.Name != authenticatedOrganizationName {
				return fmt.Errorf("organization name is not %s, but %s", customer.Name, authenticatedOrganizationName)
			}
			return nil
		}),
	)
}

func (r DemoEHR) Logout() error {
	return chromedp.Run(r.Context,
		logInfo("Logging out of Demo EHR"),
		chromedp.Navigate(r.URL),
		chromedp.Evaluate("window.localStorage.removeItem('session')", nil),
	)
}

func (r DemoEHR) RegisterPatient(patient Patient) error {
	return chromedp.Run(r.Context,
		logInfo("Registering patient: %v", patient),
		chromedp.Click("#patients-menu-link"),
		chromedp.Click("#new-patient-button", chromedp.NodeNotVisible),
		chromedp.SetValue("#ssn-input", patient.SocialSecurityNumber, chromedp.NodeVisible),
		chromedp.SetValue("#firstname-input", patient.Firstname),
		chromedp.SetValue("#surname-input", patient.Lastname),
		chromedp.SetValue("#gender-select", patient.Gender),
		chromedp.SetValue("#dob-input", patient.DateOfBirth),
		chromedp.SetValue("#zipcode-input", patient.Zipcode),
		chromedp.SetValue("#email-input", patient.Email),
		chromedp.Click("#add-patient-button"),
		chromedp.WaitVisible("*[data-patient-ssn='"+patient.SocialSecurityNumber+"']"),
	)
}

type TransferRequest struct {
	ReceiverOrganizationName string
	Date                     string
	Problem                  string
	Intervention             string
}

func (r DemoEHR) CreateAndAssignPatientTransfer(patient Patient, request TransferRequest) error {
	// We do a partial search on organization name
	var organizationSearchQuery string
	if len(request.ReceiverOrganizationName) >= 3 {
		organizationSearchQuery = request.ReceiverOrganizationName[:3]
	} else {
		organizationSearchQuery = request.ReceiverOrganizationName
	}
	return chromedp.Run(r.Context,
		logInfo("Creating and assigning transfer for patient: %v (organization: %s)", patient, request.ReceiverOrganizationName),
		// Navigate to patient
		chromedp.Click("#patients-menu-link"),
		chromedp.Click("*[data-patient-ssn='"+patient.SocialSecurityNumber+"']", chromedp.NodeVisible),
		// Create new transfer
		chromedp.Click("#new-dossier-button", chromedp.NodeVisible),
		chromedp.Click("#new-transfer-dossier-button", chromedp.NodeVisible),
		// Set transfer properties and create
		chromedp.SetValue("#transfer-date-input", request.Date, chromedp.NodeVisible),
		chromedp.SetValue("#transfer-problem-input", request.Problem),
		chromedp.SetValue("#transfer-intervention-input", request.Intervention),
		chromedp.Click("#create-transfer-button", chromedp.NodeVisible),
		// Assign transfer to organization
		chromedp.SendKeys("#transfer-receiver-input", organizationSearchQuery, chromedp.NodeVisible),
		chromedp.Click("li[role='option']", chromedp.NodeVisible), // We just assume the first one is accurate
		chromedp.Click("#transfer-assign-button", chromedp.NodeVisible),
		chromedp.Sleep(2*time.Second),
		//enable this instead?
		//chromedp.WaitVisible("div[data-message='Patient transfer assigned']"),
		//chromedp.Sleep(time.Minute),
	)
}

func (r DemoEHR) ViewTransferRequestInInbox(t *testing.T, sender CareOrganization, patient Patient) error {
	var actualSubject, actualStatus, actualSender string
	return chromedp.Run(r.Context,
		logInfo("Viewing patient transfer inbox entry (patient: %s, sending care organization: %s)", patient.SocialSecurityNumber, sender.Name),
		// Navigate to inbox
		chromedp.Click("#inbox-menu-link"),
		chromedp.Click("#elevate-dummy-button", chromedp.NodeVisible),
		// Collect values from inbox item
		chromedp.Text("table tbody tr td:nth-child(2)", &actualSubject),
		chromedp.Text("table tbody tr td:nth-child(3)", &actualStatus),
		chromedp.Text("table tbody tr td:nth-child(4)", &actualSender),
		Assert(t, func(t *testing.T) {
			assert.Equal(t, "Overdracht van zorg", actualSubject)
			assert.Equal(t, "requested", actualStatus)
			assert.Equal(t, sender.Name+", "+sender.City, actualSender)
		}),
	)
}

func (r DemoEHR) ViewTransferRequestDetails(t *testing.T, sender CareOrganization, patient Patient, request TransferRequest) error {
	var actualDate, actualCareOrganization, actualStatus,
		actualPatientName, actualPatientSSN, actualPatientGender, actualPatientDateOfBirth, actualPatientZipcode,
		actualProblemName, actualProblemIntervention string
	var pageTitle string
	return chromedp.Run(r.Context,
		logInfo("Viewing patient transfer request details (patient: %s, sending care organization: %s)", patient.SocialSecurityNumber, sender.Name),
		// Assert/assume we're on the inbox page
		chromedp.Text("h1", &pageTitle, chromedp.ByQueryAll),
		Assert(t, func(t *testing.T) {
			assert.Equal(t, "Inbox", pageTitle)
		}),
		// Click on first inbox item
		chromedp.Click("table tbody tr"),
		// Assert transfer status
		logInfo("Asserting transfer status"),
		chromedp.Text("#requesting-care-organization-info", &actualCareOrganization, chromedp.NodeVisible),
		chromedp.Text("#transfer-request-status-info", &actualStatus),
		chromedp.Text("#transfer-request-date-info", &actualDate),
		Assert(t, func(t *testing.T) {
			assert.Equal(t, request.Date, actualDate)
			assert.Equal(t, sender.Name+" in "+sender.City, actualCareOrganization)
			assert.Equal(t, "requested", actualStatus)
		}),
		// Assert transfer details
		logInfo("Asserting transfer problem details"),
		chromedp.Text("*[data-problem-detail='name']", &actualProblemName),
		chromedp.Text("*[data-problem-detail='intervention']", &actualProblemIntervention),
		Assert(t, func(t *testing.T) {
			assert.Equal(t, request.Problem, actualProblemName)
			assert.Equal(t, request.Intervention, actualProblemIntervention)
		}),
		// Assert patient details
		logInfo("Asserting transfer patient details"),
		chromedp.Text("#patient-name-label", &actualPatientName),
		chromedp.Text("#patient-ssn-label", &actualPatientSSN),
		chromedp.Text("#patient-gender-label", &actualPatientGender),
		chromedp.Text("#patient-dob-label", &actualPatientDateOfBirth),
		chromedp.Text("#patient-zipcode-label", &actualPatientZipcode),
		Assert(t, func(t *testing.T) {
			assert.Equal(t, patient.Firstname+" "+patient.Lastname, actualPatientName)
			assert.Equal(t, patient.SocialSecurityNumber, actualPatientSSN)
			assert.Equal(t, patient.Gender, actualPatientGender)
			assert.Equal(t, patient.DateOfBirth, actualPatientDateOfBirth)
			assert.Equal(t, patient.Zipcode, actualPatientZipcode)
		}),
	)
}
