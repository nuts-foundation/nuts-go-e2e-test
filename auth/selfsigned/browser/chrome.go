package browser

import (
	"context"
	"github.com/chromedp/chromedp"
)

func NewChrome(headless bool) (context.Context, context.CancelFunc) {
	var execCtx context.Context
	var execCtxCancel context.CancelFunc
	if headless {
		execCtx, execCtxCancel = chromedp.NewRemoteAllocator(context.Background(), "http://localhost:9222")
	} else {
		execCtx, execCtxCancel = chromedp.NewExecAllocator(context.Background(), append(chromedp.DefaultExecAllocatorOptions[:], chromedp.Flag("headless", false))...)
	}

	ctx, cancel := chromedp.NewContext(
		execCtx,
		//chromedp.WithDebugf(log.Printf),
	)
	go func() {
		<-ctx.Done()
		execCtxCancel()
	}()

	return ctx, cancel
}
