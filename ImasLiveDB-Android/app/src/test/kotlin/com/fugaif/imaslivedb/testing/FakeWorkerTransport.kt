package com.fugaif.imaslivedb.testing

import com.fugaif.imaslivedb.data.net.WorkerRequest
import com.fugaif.imaslivedb.data.net.WorkerResponse
import com.fugaif.imaslivedb.data.net.WorkerTransport
import java.io.IOException

/**
 * Worker への送信を差し替えるフェイク。送られたものを記録し、[respond] の返事を返す。
 * [respond] が null を返したら通信そのものの失敗 (IOException) にする。
 */
class FakeWorkerTransport(
    private val respond: (WorkerRequest) -> WorkerResponse? = { WorkerResponse(200, "{}") }
) : WorkerTransport {

    val requests = mutableListOf<WorkerRequest>()

    override fun execute(request: WorkerRequest): WorkerResponse {
        requests += request
        return respond(request) ?: throw IOException("fake: network down")
    }
}
