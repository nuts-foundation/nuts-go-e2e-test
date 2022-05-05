package apps

import (
	"context"
	"fmt"
	"github.com/chromedp/chromedp"
	"github.com/rs/zerolog/log"
	"io/ioutil"
	"net/http"
	"time"
)

type HAPI struct {
	URL string
}

func (h HAPI) WaitForReady(ctx context.Context) error {
	log.Info().Msg("Waiting for HAPI to become ready...")
	targetURL := h.URL
	return h.wait(ctx, targetURL)
}

func (h HAPI) WaitForTenant(ctx context.Context, tenantID int) error {
	log.Info().Msgf("Waiting for tenant %d to become available...", tenantID)
	targetURL := fmt.Sprintf("%s/fhir/%d/Task", h.URL, tenantID)
	return h.wait(ctx, targetURL)
}

func (h HAPI) wait(ctx context.Context, targetURL string) error {
	deadline, _ := ctx.Deadline()
	if deadline.IsZero() {
		deadline = time.Now().Add(time.Minute)
	}
	var lastError error
	client := http.Client{Timeout: 500 * time.Millisecond}
	for {
		if time.Now().After(deadline) {
			return fmt.Errorf("timeout waiting for HAPI (last error: %w)", lastError)
		}

		response, err := client.Get(targetURL)
		if err != nil {
			log.Debug().Err(err).Msg("Error while waiting for HAPI")
			lastError = err
		} else {
			log.Debug().Int("status", response.StatusCode).Msg("HAPI response")
			_, _ = ioutil.ReadAll(response.Body)
			if response.StatusCode == http.StatusOK {
				return nil
			}
		}
		chromedp.Sleep(100 * time.Millisecond)
	}
}
