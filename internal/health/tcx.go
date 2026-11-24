package health

import (
	"context"
	"errors"
	"net/url"
	"strings"
)

func (c *Client) ExportTCX(ctx context.Context, id string, partial bool) ([]byte, error) {
	if id == "" || id == "." || id == ".." || strings.ContainsAny(id, "/\\?#\x00\r\n") {
		return nil, errors.New("invalid exercise ID")
	}
	query := url.Values{"alt": {"media"}}
	if partial {
		query.Set("partialData", "true")
	}
	return c.get(ctx, c.BaseURL+"/v4/users/me/dataTypes/exercise/dataPoints/"+url.PathEscape(id)+":exportExerciseTcx?"+query.Encode())
}
