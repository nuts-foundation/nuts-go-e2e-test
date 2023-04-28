package apps

import (
	"context"
	"errors"
	"github.com/chromedp/chromedp"
	"github.com/rs/zerolog/log"
	"testing"
)

func CheckCheckbox(selector string) chromedp.ActionFunc {
	return func(ctx context.Context) error {
		return chromedp.Run(ctx, chromedp.Click(selector, chromedp.NodeVisible))
	}
}

func logInfo(msg string, args ...interface{}) chromedp.ActionFunc {
	return func(ctx context.Context) error {
		if len(args) > 0 {
			log.Info().Msgf(msg, args...)
		} else {
			log.Info().Msg(msg)
		}
		return nil
	}
}

func Assert(t *testing.T, assertion func(t *testing.T)) chromedp.ActionFunc {
	t.Helper()
	return func(ctx context.Context) error {
		assertion(t)
		if t.Failed() {
			return errors.New("assertion(s) failed")
		}
		return nil
	}
}
