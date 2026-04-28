import json

from entrypoint import handle_hosted_parser_request

try:
    import azure.functions as func
except ImportError:  # pragma: no cover - local unit tests do not need azure-functions installed
    func = None


if func is not None:
    app = func.FunctionApp(http_auth_level=func.AuthLevel.FUNCTION)

    @app.route(route="processfreightdocument", methods=["POST"])
    def process_freight_document(req: func.HttpRequest) -> func.HttpResponse:
        try:
            payload = req.get_json()
        except ValueError:
            return func.HttpResponse(
                json.dumps({"status": "error", "error": "Request body must be valid JSON."}, ensure_ascii=True),
                mimetype="application/json",
                status_code=400,
            )

        status_code, body = handle_hosted_parser_request(payload)
        return func.HttpResponse(
            json.dumps(body, ensure_ascii=True),
            mimetype="application/json",
            status_code=status_code,
        )

