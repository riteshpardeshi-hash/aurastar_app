const { onDocumentCreated } = require('firebase-functions/v2/firestore');
const { setGlobalOptions } = require('firebase-functions/v2');
const { defineString } = require('firebase-functions/params');
const { GoogleGenerativeAI } = require('@google/generative-ai');
const { GoogleAIFileManager } = require('@google/generative-ai/server');
const admin = require('firebase-admin');
const fs = require('fs');
const os = require('os');
const path = require('path');

setGlobalOptions({ maxInstances: 10, memory: '1GiB', timeoutSeconds: 300 });

admin.initializeApp();
const db = admin.firestore();

const GEMINI_API_KEY = defineString('GEMINI_API_KEY');

async function downloadToTemp(url, filename) {
  const response = await fetch(url);
  if (!response.ok) throw new Error(`Download failed (${response.status}): ${url}`);
  const buffer = Buffer.from(await response.arrayBuffer());
  const tempPath = path.join(os.tmpdir(), filename);
  fs.writeFileSync(tempPath, buffer);
  return tempPath;
}

async function uploadVideoToGemini(fileManager, filePath, displayName) {
  const result = await fileManager.uploadFile(filePath, {
    mimeType: 'video/mp4',
    displayName,
  });
  let file = result.file;
  while (file.state === 'PROCESSING') {
    await new Promise(r => setTimeout(r, 3000));
    file = await fileManager.getFile(file.name);
  }
  if (file.state === 'FAILED') throw new Error(`Gemini processing failed for: ${displayName}`);
  return file;
}

// Applies the daily valid score limit rule.
// Only the top N approved scores per day count for Auras.
// Returns { isCountedForDailyAuras, netAurasAwarded }.
// Also creates auraTransaction records and updates totalRewards.
async function applyDailyScoreLimit(submissionId, userId, auraPoints, score, challengeTitle) {
  const userDoc = await db.collection('users').doc(userId).get();
  const dailyLimit = (userDoc.data() || {}).dailyValidScoreLimit ?? 3;

  const todayStart = new Date();
  todayStart.setHours(0, 0, 0, 0);
  const todayTimestamp = admin.firestore.Timestamp.fromDate(todayStart);

  // Query today's submissions that already count for daily Auras (requires composite index:
  // submissions: userId ASC, isCountedForDailyAuras ASC, createdAt ASC)
  const todaySnap = await db.collection('submissions')
    .where('userId', '==', userId)
    .where('isCountedForDailyAuras', '==', true)
    .where('createdAt', '>=', todayTimestamp)
    .get();

  const todayCounted = todaySnap.docs
    .filter(d => d.id !== submissionId)
    .map(d => ({ id: d.id, points: (d.data().auraPoints || 0) }));

  todayCounted.sort((a, b) => b.points - a.points); // highest first

  let isCountedForDailyAuras = false;
  let netAurasAwarded = 0;

  if (todayCounted.length < dailyLimit) {
    // Open slot available — full score counts
    isCountedForDailyAuras = true;
    netAurasAwarded = auraPoints;
  } else {
    const lowest = todayCounted[todayCounted.length - 1];
    if (auraPoints > lowest.points) {
      // New score beats the lowest counted score — replace it
      isCountedForDailyAuras = true;
      netAurasAwarded = auraPoints - lowest.points;

      await db.collection('submissions').doc(lowest.id).update({
        isCountedForDailyAuras: false,
      });

      // Negative transaction for the score being replaced
      await db.collection('auraTransactions').add({
        userId,
        amount: -lowest.points,
        type: 'daily_score_replacement',
        sourceId: lowest.id,
        description: `Previous score replaced by a better attempt`,
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
      });
    }
    // else: doesn't enter top N — no Auras awarded
  }

  if (netAurasAwarded > 0) {
    await db.collection('users').doc(userId).update({
      totalRewards: admin.firestore.FieldValue.increment(netAurasAwarded),
    });
  }

  // Record this submission's transaction
  await db.collection('auraTransactions').add({
    userId,
    amount: netAurasAwarded,
    type: 'challenge_score',
    sourceId: submissionId,
    description: isCountedForDailyAuras
      ? `Scored ${score}/100 on "${challengeTitle}" — +${netAurasAwarded} Auras`
      : `Scored ${score}/100 on "${challengeTitle}" — didn't enter your top ${dailyLimit} today`,
    isCountedForDailyAuras,
    dailyLimit,
    createdAt: admin.firestore.FieldValue.serverTimestamp(),
  });

  console.log(`[applyDailyScoreLimit] ${submissionId}: counted=${isCountedForDailyAuras}, net=${netAurasAwarded}, daily slots used=${todayCounted.length}/${dailyLimit}`);
  return { isCountedForDailyAuras, netAurasAwarded };
}

// ─────────────────────────────────────────────────────────────────────────────
// STEP 1: When a challenge is created, Gemini watches the reference video and
//         generates 10-15 specific YES/NO checklist questions for scoring.
// ─────────────────────────────────────────────────────────────────────────────
exports.generateScoringRubric = onDocumentCreated('challenges/{challengeId}', async (event) => {
  const challenge = event.data.data();
  const challengeRef = event.data.ref;
  const challengeId = event.params.challengeId;

  if (!challenge.videoUrl) {
    console.log(`[generateScoringRubric] No videoUrl on challenge ${challengeId}, skipping.`);
    return;
  }

  const apiKey = GEMINI_API_KEY.value();
  if (!apiKey) {
    console.error('[generateScoringRubric] GEMINI_API_KEY not configured.');
    return;
  }

  const fileManager = new GoogleAIFileManager(apiKey);
  const uploadedFileNames = [];
  const tempFiles = [];

  try {
    const refTempPath = await downloadToTemp(challenge.videoUrl, `rubric_ref_${challengeId}.mp4`);
    tempFiles.push(refTempPath);

    const refFile = await uploadVideoToGemini(fileManager, refTempPath, 'reference_video');
    uploadedFileNames.push(refFile.name);

    const genAI = new GoogleGenerativeAI(apiKey);
    const model = genAI.getGenerativeModel({ model: 'gemini-2.5-flash' });

    const checklistResult = await model.generateContent({
      contents: [{
        role: 'user',
        parts: [
          { fileData: { mimeType: 'video/mp4', fileUri: refFile.uri } },
          {
            text: `Watch this reference video for the challenge: "${challenge.title}"
${challenge.description ? `Description: ${challenge.description}` : ''}
${challenge.instructions ? `Instructions: ${challenge.instructions}` : ''}

Your job: Generate exactly 10 YES/NO checklist questions that an AI judge will use to verify whether a user-submitted video correctly completes this challenge.

Rules for each question:
- Must be answerable with a definitive YES or NO just by watching the video
- Must describe one specific, visible action, position, or step from the reference video
- Must cover the challenge from beginning to end in order
- Be concrete: name body parts, objects, positions, counts, or sequences
- A person who only did half the challenge should answer NO to roughly 7-8 of these questions
- Make questions strict — a sloppy or partial attempt at a step should still be a NO

BAD question: "Did the user attempt to play guitar?" (too easy to say YES)
GOOD question: "Did the user's index finger press the B string at the 2nd fret cleanly without muting adjacent strings?" (strict and specific)

Output ONLY a JSON array of exactly 15 strings — no explanation, no title, nothing else:
["question 1", "question 2", "question 3", "question 4", "question 5", "question 6", "question 7", "question 8", "question 9", "question 10", "question 11", "question 12", "question 13", "question 14", "question 15"]`,
          },
        ],
      }],
      generationConfig: { responseMimeType: 'application/json' },
    });

    const checklist = JSON.parse(checklistResult.response.text().trim());

    if (!Array.isArray(checklist) || checklist.length === 0) {
      throw new Error('Gemini did not return a valid checklist array.');
    }

    const promptResult = await model.generateContent({
      contents: [{
        role: 'user',
        parts: [
          { fileData: { mimeType: 'video/mp4', fileUri: refFile.uri } },
          {
            text: `Watch this reference video for the challenge: "${challenge.title}"
${challenge.description ? `Description: ${challenge.description}` : ''}
${challenge.instructions ? `Instructions: ${challenge.instructions}` : ''}

Your job: Write a scoring prompt that will be used by an AI judge to evaluate user-submitted videos for this challenge.

The prompt you write will be appended after two videos (the reference video and the user's submission video) and sent to an AI. It must:
1. Tell the AI what specific actions, steps, and quality standards to look for (derived from what you see in the reference video)
2. Describe a strict 0–100 scoring rubric with clear thresholds
3. End with an instruction to respond with ONLY this JSON: {"score": <integer 0-100>, "short_feedback": "<one sentence what was done well> <one sentence what was missing or wrong>"}

Rules for the prompt:
- Be specific about observable actions (body positions, object use, sequence, counts, timing)
- Be strict: partial completion should score below 50
- Reference "the REFERENCE video" and "the USER SUBMISSION" by those exact names
- Do NOT wrap the prompt in JSON — output plain text only
- Do NOT include any preamble or explanation — output only the prompt text itself`,
          },
        ],
      }],
    });

    const aiScoringPrompt = promptResult.response.text().trim();

    if (!aiScoringPrompt) {
      throw new Error('Gemini did not return a valid scoring prompt.');
    }

    await challengeRef.update({
      aiScoringChecklist: checklist,
      aiScoringPrompt,
      aiRubricGeneratedAt: admin.firestore.FieldValue.serverTimestamp(),
    });

    console.log(`[generateScoringRubric] Checklist and scoring prompt saved for ${challengeId} (${checklist.length} questions).`);

  } catch (err) {
    console.error(`[generateScoringRubric] Error for ${challengeId}:`, err.message);
  } finally {
    for (const p of tempFiles) { try { fs.unlinkSync(p); } catch (_) {} }
    for (const name of uploadedFileNames) { try { await fileManager.deleteFile(name); } catch (_) {} }
  }
});

// ─────────────────────────────────────────────────────────────────────────────
// STEP 2: Score each submission using the checklist.
//         Gemini answers YES/NO per question. Score = (yesCount / total) * 100.
//         Daily valid score limit is applied — only top N scores earn Auras.
// ─────────────────────────────────────────────────────────────────────────────
exports.scoreSubmission = onDocumentCreated('submissions/{submissionId}', async (event) => {
  const submission = event.data.data();
  const submissionRef = event.data.ref;
  const submissionId = event.params.submissionId;

  const apiKey = GEMINI_API_KEY.value();
  if (!apiKey) {
    await submissionRef.update({ status: 'ai_error', aiError: 'GEMINI_API_KEY not configured' });
    return;
  }

  const fileManager = new GoogleAIFileManager(apiKey);
  const uploadedFileNames = [];
  const tempFiles = [];

  try {
    const challengeDoc = await db.collection('challenges').doc(submission.challengeId).get();
    if (!challengeDoc.exists) {
      await submissionRef.update({ status: 'ai_error', aiError: 'Challenge not found' });
      return;
    }
    const challenge = challengeDoc.data();

    // Upload user submission
    const userTempPath = await downloadToTemp(submission.videoUrl, `user_${submissionId}.mp4`);
    tempFiles.push(userTempPath);
    const userFile = await uploadVideoToGemini(fileManager, userTempPath, 'user_submission');
    uploadedFileNames.push(userFile.name);

    const genAI = new GoogleGenerativeAI(apiKey);
    const model = genAI.getGenerativeModel({ model: 'gemini-2.5-flash' });

    let score, approved, auraPoints, reason;

    const manualPrompt = challenge.aiScoringPrompt;
    const checklist = challenge.aiScoringChecklist;

    if (manualPrompt && typeof manualPrompt === 'string' && manualPrompt.trim().length > 0) {
      // ── MANUAL PROMPT PATH: user wrote custom scoring instructions ────────
      // The prompt is used as-is — no output format appended.
      // Supports both simple prompts and detailed rubrics with custom JSON output.
      let refFile = null;
      if (challenge.videoUrl) {
        const refTempPath = await downloadToTemp(challenge.videoUrl, `ref_${submission.challengeId}.mp4`);
        tempFiles.push(refTempPath);
        refFile = await uploadVideoToGemini(fileManager, refTempPath, 'reference_video');
        uploadedFileNames.push(refFile.name);
      }

      const parts = [];
      if (refFile) {
        parts.push({ fileData: { mimeType: 'video/mp4', fileUri: refFile.uri } });
        parts.push({ text: 'This is the REFERENCE video.' });
      }
      parts.push({ fileData: { mimeType: 'video/mp4', fileUri: userFile.uri } });
      parts.push({ text: manualPrompt.trim() });

      const result = await model.generateContent({
        contents: [{ role: 'user', parts }],
        generationConfig: { responseMimeType: 'application/json' },
      });

      const ai = JSON.parse(result.response.text().trim());

      // Flexibly extract score — supports both simple {"score":n} and
      // detailed rubrics that return {"total_score":n, ...}
      const rawScore = ai.total_score ?? ai.score ?? 0;
      score = Math.min(100, Math.max(0, Math.round(Number(rawScore) || 0)));
      approved = score >= 10;
      auraPoints = approved ? score : 0;

      // Flexibly extract user-facing reason
      reason = String(ai.short_feedback ?? ai.reason ?? ai.feedback ?? 'AI review complete.');

      console.log(`[scoreSubmission] ${submissionId}: manual prompt → score ${score}`);

      const { isCountedForDailyAuras, netAurasAwarded } = approved
        ? await applyDailyScoreLimit(submissionId, submission.userId, auraPoints, score, challenge.title)
        : { isCountedForDailyAuras: false, netAurasAwarded: 0 };

      await submissionRef.update({
        status: approved ? 'approved' : 'rejected',
        auraPoints,
        netAurasAwarded,
        isCountedForDailyAuras,
        aiScore: score,
        aiReason: reason,
        aiFullResponse: ai,           // full detailed breakdown stored here
        reviewedByAI: true,
        usedManualPrompt: true,
        reviewedAt: admin.firestore.FieldValue.serverTimestamp(),
      });

    } else if (Array.isArray(checklist) && checklist.length > 0) {
      // ── CHECKLIST PATH: YES/NO per question, score counted in code ──────────
      const questionLines = checklist.map((q, i) => `${i + 1}. ${q}`).join('\n');

      const result = await model.generateContent({
        contents: [{
          role: 'user',
          parts: [
            { fileData: { mimeType: 'video/mp4', fileUri: userFile.uri } },
            {
              text: `Watch this video of someone attempting the challenge: "${challenge.title}"

Answer each question below with ONLY "YES" or "NO".

Rules:
- YES only if the action is performed correctly, completely, and matches what the reference expects — no exceptions
- NO if the action is missing, wrong, sloppy, rushed, unclear, or only partially done
- NO if you have even the slightest doubt
- Never give benefit of the doubt — a near-miss is still a NO

Questions:
${questionLines}

Respond with ONLY this JSON (no markdown, no explanation):
{
  "answers": ["YES or NO", "YES or NO", ...],
  "reason": "<one sentence about what the user did well> <one sentence about what was missing or incomplete>"
}

The answers array must have exactly ${checklist.length} entries in the same order as the questions.`,
            },
          ],
        }],
        generationConfig: { responseMimeType: 'application/json' },
      });

      const ai = JSON.parse(result.response.text().trim());
      const answers = Array.isArray(ai.answers) ? ai.answers : [];

      // Score is calculated entirely in code — AI cannot inflate it
      const yesCount = answers.filter(a => String(a).trim().toUpperCase() === 'YES').length;
      score = Math.round((yesCount / checklist.length) * 100);
      approved = score >= 10;
      auraPoints = approved ? score : 0;
      reason = String(ai.reason || 'AI review complete.');

      console.log(`[scoreSubmission] ${submissionId}: ${yesCount}/${checklist.length} YES → score ${score}`);

      // Apply daily score limit (handles totalRewards increment and transaction creation)
      const { isCountedForDailyAuras, netAurasAwarded } = approved
        ? await applyDailyScoreLimit(submissionId, submission.userId, auraPoints, score, challenge.title)
        : { isCountedForDailyAuras: false, netAurasAwarded: 0 };

      await submissionRef.update({
        status: approved ? 'approved' : 'rejected',
        auraPoints,
        netAurasAwarded,
        isCountedForDailyAuras,
        aiScore: score,
        aiReason: reason,
        reviewedByAI: true,
        usedAiChecklist: true,
        aiChecklistAnswers: checklist.map((q, i) => ({
          question: q,
          answer: answers[i] || 'NO',
        })),
        reviewedAt: admin.firestore.FieldValue.serverTimestamp(),
      });

    } else {
      // ── FALLBACK PATH: no checklist, upload reference and do comparison ─────
      let refFile = null;
      if (challenge.videoUrl) {
        const refTempPath = await downloadToTemp(challenge.videoUrl, `ref_${submission.challengeId}.mp4`);
        tempFiles.push(refTempPath);
        refFile = await uploadVideoToGemini(fileManager, refTempPath, 'reference_video');
        uploadedFileNames.push(refFile.name);
      }

      const parts = [];
      if (refFile) {
        parts.push({ fileData: { mimeType: 'video/mp4', fileUri: refFile.uri } });
        parts.push({ text: 'This is the REFERENCE video.' });
      }
      parts.push({ fileData: { mimeType: 'video/mp4', fileUri: userFile.uri } });
      parts.push({
        text: `This is the USER SUBMISSION for challenge: "${challenge.title}"
${challenge.description ? `Description: ${challenge.description}` : ''}

${refFile
  ? 'Compare the submission against the reference. Count how many of the key steps from the reference the user completed.'
  : 'Judge how completely the user performed this challenge based on the description.'}

Score strictly: if roughly half the steps were done, the score must be around 50, not 80 or 100.

Respond with ONLY this JSON:
{"score": <integer 0-100>, "approved": <true if score >= 10>, "reason": "<what was done correctly> <what was missing>"}`,
      });

      const result = await model.generateContent({
        contents: [{ role: 'user', parts }],
        generationConfig: { responseMimeType: 'application/json' },
      });

      const ai = JSON.parse(result.response.text().trim());
      score = Math.min(100, Math.max(0, Math.round(Number(ai.score) || 0)));
      approved = score >= 10;
      auraPoints = approved ? score : 0;
      reason = String(ai.reason || 'AI review complete.');

      // Apply daily score limit (handles totalRewards increment and transaction creation)
      const { isCountedForDailyAuras, netAurasAwarded } = approved
        ? await applyDailyScoreLimit(submissionId, submission.userId, auraPoints, score, challenge.title)
        : { isCountedForDailyAuras: false, netAurasAwarded: 0 };

      await submissionRef.update({
        status: approved ? 'approved' : 'rejected',
        auraPoints,
        netAurasAwarded,
        isCountedForDailyAuras,
        aiScore: score,
        aiReason: reason,
        reviewedByAI: true,
        usedAiChecklist: false,
        reviewedAt: admin.firestore.FieldValue.serverTimestamp(),
      });
    }

  } catch (err) {
    console.error(`[scoreSubmission] Error for ${submissionId}:`, err);
    await submissionRef.update({
      status: 'ai_error',
      aiError: (err.message || 'Unknown error').slice(0, 500),
    });
  } finally {
    for (const p of tempFiles) { try { fs.unlinkSync(p); } catch (_) {} }
    for (const name of uploadedFileNames) { try { await fileManager.deleteFile(name); } catch (_) {} }
  }
});
