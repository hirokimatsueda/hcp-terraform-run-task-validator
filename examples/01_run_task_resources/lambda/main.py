import datetime
import os
import json
import hmac
import hashlib
import urllib.request
import urllib.error
from typing import Dict, Any


def get_parameter(name: str) -> str:
    """Parameter Store Extension API からパラメータを取得

    AWS Lambda Extension for Parameter Store を使用して、
    Parameter Store からパラメータを取得します。
    withDecryption=true を指定することで、SecureString 型の値を復号化して取得します。

    Args:
        name: パラメータ名

    Returns:
        パラメータの値（SecureString の場合は復号化された値）
    """
    url = f"http://localhost:2773/systemsmanager/parameters/get?name={name}&withDecryption=true"
    headers = {
        "X-Aws-Parameters-Secrets-Token": os.environ.get("AWS_SESSION_TOKEN", "")
    }
    req = urllib.request.Request(url, headers=headers)
    with urllib.request.urlopen(req) as res:
        response = json.loads(res.read())
        return response["Parameter"]["Value"]


def get_plan_json(request_body: Any):
    """Plan 結果の Json の取得

    Args:
        request_body: リクエストボディ

    Returns:
        Plan 結果の Json
    """
    url = request_body.get("plan_json_api_url")
    access_token = request_body.get("access_token")

    headers = {
        "Authorization": f"Bearer {access_token}",
        "Content-type": "application/vnd.api+json",
    }
    req = urllib.request.Request(url, headers=headers)
    with urllib.request.urlopen(req) as res:
        response = json.loads(res.read())
        return response


def verify_hmac(payload: str, signature: str, secret: str) -> bool:
    """HMAC 署名を検証

    HCP Terraform からのリクエストの HMAC 署名を検証します。
    SHA-512 ハッシュアルゴリズムを使用し、タイミング攻撃を防ぐために
    hmac.compare_digest を使用して比較を行います。

    Args:
        payload: 署名対象のペイロード
        signature: リクエストヘッダーの HMAC 署名
        secret: HMAC 署名の秘密鍵

    Returns:
        署名が有効な場合は True、それ以外は False
    """
    computed = hmac.new(secret.encode(), payload.encode(), hashlib.sha512).hexdigest()
    return hmac.compare_digest(computed, signature)


def notify_result(request_body: Any, status: str, message: str) -> None:
    """HCP Terraform に Run Task 結果を通知

    Run Task の実行結果を HCP Terraform に通知します。
    コールバック URL とアクセストークンは、リクエストペイロードから取得した値を使用します。

    Args:
        request_body: リクエストボディ
        status: 実行結果のステータス（"passed" or "failed"）
        message: 実行結果のメッセージ
    """
    callback_url = request_body.get("task_result_callback_url")
    access_token = request_body.get("access_token")

    headers = {
        "Authorization": f"Bearer {access_token}",
        "Content-Type": "application/vnd.api+json",
    }
    payload = {
        "data": {
            "type": "task-results",
            "attributes": {"status": status, "message": message},
        }
    }
    data = json.dumps(payload).encode()
    req = urllib.request.Request(
        url=callback_url, data=data, headers=headers, method="PATCH"
    )
    urllib.request.urlopen(req)


def handler(event: Dict[str, Any], context: Any) -> Dict[str, Any]:
    """Lambda 関数のメインハンドラー

    HCP Terraform の Run Task リクエストを処理します。
    1. HMAC 署名の検証
    2. Run Task 設定時の検証応答
    3. Run 実行時の検証処理
    の 3 つの主要な処理を行います。

    Run Task 設定時（task_result_enforcement_level = "test"）は、
    HMAC 署名の検証のみを行い、成功レスポンスを返します。

    Run 実行時は、Terraform 実行計画の検証を行い、
    結果をコールバック URL に通知します。

    Args:
        event: Lambda Function URL からのイベント
        context: Lambda 実行コンテキスト

    Returns:
        Lambda Function URL のレスポンス
    """
    try:
        # パラメータストアからシークレット取得
        hmac_key = get_parameter(os.environ["HMAC_SECRET_KEY_PARAM"])

        # リクエストの解析
        body = json.loads(event.get("body", "{}"))
        headers = event.get("headers", {})
        signature = headers.get("x-tfc-task-signature", "")

        # HMAC署名の検証
        if not verify_hmac(event["body"], signature, hmac_key):
            return {
                "statusCode": 401,
                "body": json.dumps({"message": "Invalid signature"}),
            }

        # Run Task設定時 (task_result_enforcement_level が "test" の場合) は、HMAC検証成功で応答
        if body.get("task_result_enforcement_level") == "test":
            return {
                "statusCode": 200,
                "body": json.dumps(
                    {
                        "data": {
                            "type": "task-results",
                            "attributes": {
                                "status": "passed",
                                "message": "Configuration successful",
                            },
                        }
                    }
                ),
            }

        # Plan 結果の取得
        plan_json = get_plan_json(body)
        plan_timestamp = datetime.datetime.fromisoformat(plan_json["timestamp"])

        # 検証ロジックの実装
        # ダミーの実装として、Plan 結果の timestamp の「分」が偶数なら成功、奇数ならエラーとする
        if plan_timestamp.minute % 2 == 0:
            validation_passed = True
            message = "Validation passed"
        else:
            validation_passed = False
            message = "Validation failed"
        print(f"validation_passed = {validation_passed}")

        # 結果を HCP Terraform に通知
        status = "passed" if validation_passed else "failed"
        print(f"status = {status}")
        notify_result(body, status, message)

        return {
            "statusCode": 200,
            "body": json.dumps(
                {
                    "data": {
                        "type": "task-results",
                        "attributes": {"status": status, "message": message},
                    }
                }
            ),
        }

    except Exception as e:
        import traceback

        print(f"Error: {str(e)}")
        print(f"Traceback: {traceback.format_exc()}")
        return {
            "statusCode": 500,
            "body": json.dumps({"message": f"Internal error: {str(e)}"}),
        }
