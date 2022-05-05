package apps

import (
	"context"
	"fmt"
	"github.com/chromedp/cdproto/cdp"
	"github.com/chromedp/chromedp"
	"time"
)

type RegistryAdmin struct {
	URL     string
	Context context.Context
}

type Vendor struct {
	Name             string
	Email            string
	Website          string
	NutsNodeEndpoint string
}

type Service struct {
	Name      string
	Endpoints map[string]string
}

type Endpoint struct {
	Type string
	URL  string
}

type CareOrganization struct {
	Name string
	City string
}

type Customer struct {
	CareOrganization
	InternalID int
	Domain     string
}

func (r RegistryAdmin) Login() error {
	return chromedp.Run(r.Context,
		chromedp.Navigate(r.URL),
		chromedp.SetValue("#username_input", "demo@nuts.nl", chromedp.NodeVisible),
		chromedp.SetValue("#password_input", "demo"),
		chromedp.Click("#login_button"),
		chromedp.WaitVisible("#vendor-menu-link"),
	)
}

// IsSetUp tries to determine if the vendor (and its customers) are set up. If the vendor has a DID,
// it assumes that the vendor is set up. This makes test development quicker because it can skip the set up flow,
// if already set up.
func (r RegistryAdmin) IsSetUp() bool {
	var nodes []*cdp.Node
	_ = chromedp.Run(r.Context,
		logInfo("Checking whether the vendor is already set up..."),
		chromedp.Click(`#vendor-menu-link`),
		chromedp.WaitVisible("#name-input"),
		chromedp.Nodes("#did-input", &nodes, chromedp.AtLeast(0)),
	)
	return len(nodes) > 0
}

func (r RegistryAdmin) RegisterVendor(vendor Vendor) error {
	return chromedp.Run(r.Context,
		logInfo("Registering vendor: %v", vendor),
		chromedp.Click(`#vendor-menu-link`),
		chromedp.SetValue("#name-input", vendor.Name, chromedp.NodeVisible),
		chromedp.SetValue("#email-input", vendor.Email),
		chromedp.SetValue("#website-input", vendor.Website),
		chromedp.SetValue("#endpoint-input", vendor.NutsNodeEndpoint),
		chromedp.Click("#create-update-button", chromedp.NodeVisible),
		chromedp.WaitVisible("#did-input"),
	)
}

func (r RegistryAdmin) RegisterEndpoint(endpoint Endpoint) error {
	return chromedp.Run(r.Context,
		logInfo("Registering endpoint: %v", endpoint),
		chromedp.Click(`#vendor-menu-link`, chromedp.NodeVisible),
		chromedp.Click("#create-endpoint-button", chromedp.NodeVisible),
		chromedp.SetValue("#endpoint-type-input", endpoint.Type),
		chromedp.SetValue("#endpoint-url-input", endpoint.URL),
		chromedp.Click(`//*[text()="Register"]`, chromedp.NodeVisible),
		chromedp.Sleep(time.Second),
	)
}

func (r RegistryAdmin) RegisterService(service Service) error {
	var endpointOpts []*cdp.Node

	if err := chromedp.Run(r.Context,
		logInfo("Registering service: %v", service),
		chromedp.Click(`#vendor-menu-link`, chromedp.NodeVisible),
		chromedp.Click("#create-service-button", chromedp.NodeVisible),
		chromedp.SetValue("#service-name-input", service.Name),
	); err != nil {
		return err
	}

	// Register endpoints on compound service
	endpointSelectOptions := make(map[string]string)
	if err := chromedp.Run(r.Context,
		chromedp.Nodes("#endpoint-reference-input > option", &endpointOpts),
		chromedp.ActionFunc(func(ctx context.Context) error {
			for _, option := range endpointOpts {
				endpointSelectOptions[option.Children[0].NodeValue] = option.Attributes[1]
			}
			return nil
		})); err != nil {
		return err
	}
	var actions []chromedp.Action
	for endpointType, endpointRef := range service.Endpoints {
		actions = append(actions,
			logInfo("  Adding endpoint to service: type=%s, ref=%s", endpointType, endpointRef),
			chromedp.SetValue("#endpoint-type-input", endpointType),
			chromedp.SetValue(`#endpoint-reference-input`, endpointSelectOptions[endpointRef]),
			chromedp.Click("#add-endpoint-button", chromedp.NodeVisible),
		)
	}

	// Click "Register" button and wait for the modal to close
	actions = append(actions,
		chromedp.Click("//button[text()='Register']"),
		chromedp.WaitNotPresent("#endpoint-type-input"),
	)

	return chromedp.Run(r.Context, actions...)
}

func (r RegistryAdmin) RegisterCustomer(customer Customer) error {
	return chromedp.Run(r.Context,
		logInfo("Registering customer: %v", customer),
		chromedp.Click(`#careorganizations-menu-link`, chromedp.NodeVisible),
		chromedp.Click("#new-customer-button", chromedp.NodeVisible),
		chromedp.SetValue("#customer-id-input", fmt.Sprintf("%d", customer.InternalID)),
		chromedp.SetValue("#customer-name-input", customer.Name),
		chromedp.SetValue("#customer-city-input", customer.City),
		chromedp.SetValue("#customer-domain-input", customer.Domain),
		chromedp.Click(`//*[text()="Connect Customer"]`, chromedp.NodeVisible),
		chromedp.Sleep(time.Second),
	)
}

func (r RegistryAdmin) PublishCustomer(internalID int, services ...string) error {
	actions := []chromedp.Action{
		logInfo("Publishing customer: %d", internalID),
		chromedp.Click(`#careorganizations-menu-link`, chromedp.NodeVisible),
		chromedp.Click(fmt.Sprintf(`//td[text()="%d"]`, internalID), chromedp.NodeVisible),
		CheckCheckbox("#customer-publish-checkbox"),
	}
	for _, service := range services {
		actions = append(actions, CheckCheckbox(fmt.Sprintf("input[data-service-name='%s']", service)))
	}
	actions = append(actions,
		chromedp.Click(`//*[text()="Save Customer"]`, chromedp.NodeVisible),
		chromedp.Sleep(time.Second),
	)
	return chromedp.Run(r.Context, actions...)
}
