function getCSRFToken() {
  const meta = document.querySelector('meta[name="csrf-token"]');
  return meta ? meta.getAttribute("content") : "";
}

async function request(url, options = {}) {
  const headers = {
    "Content-Type": "application/json",
    Accept: "application/json",
    "x-csrf-token": getCSRFToken(),
    ...options.headers,
  };

  const response = await fetch(url, { ...options, headers });

  if (!response.ok) {
    const errorBody = await response.text();
    let message;
    try {
      const parsed = JSON.parse(errorBody);
      message = parsed.error || parsed.message || response.statusText;
    } catch {
      message = response.statusText;
    }
    throw new Error(message);
  }

  return response.json();
}

export function saveExamContent(examId, content) {
  return request(`/api/exams/${examId}/content`, {
    method: "PUT",
    body: JSON.stringify({ content }),
  });
}

export function saveExamSubmissionContent(token, content) {
  return request(`/api/guest/exam/${token}/content`, {
    method: "PUT",
    body: JSON.stringify({ content }),
  });
}

export function saveExamSampleSolutionPart(examId, partId, nodes) {
  return request(`/api/exams/${examId}/sample-solution/parts/${partId}/content`, {
    method: "PUT",
    body: JSON.stringify({ nodes }),
  });
}

export function saveExamCorrectionPart(examId, submissionId, partId, nodes) {
  return request(
    `/api/exams/${examId}/submissions/${submissionId}/parts/${partId}/content`,
    {
      method: "PUT",
      body: JSON.stringify({ nodes }),
    },
  );
}
