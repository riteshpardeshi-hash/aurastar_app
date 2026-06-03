const { onDocumentCreated } = require('firebase-functions/v2/firestore');
const { onSchedule } = require('firebase-functions/v2/scheduler');
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

// Per-challenge best-attempt logic.
// Only the highest score for a given challenge ever counts.
// If the new score beats the previous best, the old best is archived (7-day delete).
// Returns { isBestForChallenge, netAurasAwarded }.
async function applyBestAttemptLogic(submissionId, userId, auraPoints, score, challengeId, challengeTitle) {
  const sevenDaysMs = 7 * 24 * 60 * 60 * 1000;
  const sevenDaysFromNow = admin.firestore.Timestamp.fromDate(new Date(Date.now() + sevenDaysMs));

  // Find the user's current best submission for this challenge
  const bestSnap = await db.collection('submissions')
    .where('userId', '==', userId)
    .where('challengeId', '==', challengeId)
    .where('isBestForChallenge', '==', true)
    .limit(1)
    .get();

  let isBestForChallenge = false;
  let netAurasAwarded = 0;

  if (bestSnap.empty) {
    // First scored attempt for this challenge — it is automatically the best
    isBestForChallenge = true;
    netAurasAwarded = auraPoints;
  } else {
    const prevDoc = bestSnap.docs[0];
    const prevData = prevDoc.data();
    const prevScore = prevData.aiScore || 0;
    const prevAuras = prevData.auraPoints || 0;

    if (score > prevScore) {
      // New attempt beats the previous best
      isBestForChallenge = true;
      netAurasAwarded = Math.max(0, auraPoints - prevAuras); // net improvement only

      // Archive the old best with a 7-day delete timer
      await prevDoc.ref.update({
        isBestForChallenge: false,
        isArchived: true,
        isPublic: false,
        archiveDeleteAt: sevenDaysFromNow,
        archivedReason: 'lower_score',
      });

      // Reverse the old auras before crediting the new total
      if (prevAuras > 0) {
        await db.collection('users').doc(userId).update({
          totalRewards: admin.firestore.FieldValue.increment(-prevAuras),
        });
        await db.collection('auraTransactions').add({
          userId,
          amount: -prevAuras,
          type: 'best_attempt_replaced',
          sourceId: prevDoc.id,
          description: `Previous best (${prevScore}/100) replaced by score ${score}/100 on "${challengeTitle}"`,
          createdAt: admin.firestore.FieldValue.serverTimestamp(),
        });
      }
    }
    // else: new score is not better — isBestForChallenge stays false, netAurasAwarded stays 0
  }

  // Credit Auras for the new best
  if (netAurasAwarded > 0) {
    await db.collection('users').doc(userId).update({
      totalRewards: admin.firestore.FieldValue.increment(netAurasAwarded),
    });
  }

  // Transaction record for this submission
  await db.collection('auraTransactions').add({
    userId,
    amount: netAurasAwarded,
    type: 'challenge_score',
    sourceId: submissionId,
    description: isBestForChallenge
      ? `New best! ${score}/100 on "${challengeTitle}" — +${netAurasAwarded} Auras`
      : `${score}/100 on "${challengeTitle}" — not your best, no Auras earned`,
    isBestForChallenge,
    createdAt: admin.firestore.FieldValue.serverTimestamp(),
  });

  console.log(`[applyBestAttemptLogic] ${submissionId}: best=${isBestForChallenge}, net=${netAurasAwarded}, score=${score}`);
  return { isBestForChallenge, netAurasAwarded };
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
// STREAK: Called after every approved submission. Tracks the 7-day streak
// and credits +50 Auras on Day 7, then resets the cycle.
// ─────────────────────────────────────────────────────────────────────────────
async function applyStreakBonus(submissionId, userId) {
  try {
    const userRef = db.collection('users').doc(userId);
    const userDoc = await userRef.get();
    const userData = userDoc.data() || {};

    const tz = userData.streakTimezone || 'Asia/Kolkata';
    const today = new Date().toLocaleDateString('en-CA', { timeZone: tz });

    const lastStreakDate = userData.lastStreakDate || '';
    if (lastStreakDate === today) return; // already qualified today

    const yesterdayDate = new Date();
    yesterdayDate.setDate(yesterdayDate.getDate() - 1);
    const yesterday = yesterdayDate.toLocaleDateString('en-CA', { timeZone: tz });

    let streakDay = typeof userData.streakDay === 'number' ? userData.streakDay : 0;

    if (lastStreakDate === yesterday) {
      streakDay += 1; // consecutive day
    } else {
      streakDay = 1;  // streak broken or first ever
    }

    if (streakDay >= 7) {
      // Bonus day — credit +50 Auras and reset
      await userRef.update({
        streakDay: 0,
        lastStreakDate: today,
        totalRewards: admin.firestore.FieldValue.increment(50),
      });

      await db.collection('auraTransactions').add({
        userId,
        amount: 50,
        type: 'streak_bonus',
        sourceId: submissionId,
        description: '🔥 7-Day Streak Bonus! +50 Auras',
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
      });

      await db.collection('notifications').add({
        userId,
        type: 'streak_bonus',
        message: '🔥 7-Day Streak complete! You earned +50 Auras. New cycle starts now.',
        isRead: false,
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
      });

      console.log(`[applyStreakBonus] ${userId}: Day 7 complete — +50 Auras, streak reset.`);
    } else {
      await userRef.update({ streakDay, lastStreakDate: today });

      // Progress notification on days 3, 5, 6 only
      if ([3, 5, 6].includes(streakDay)) {
        await db.collection('notifications').add({
          userId,
          type: 'streak_progress',
          message: `🔥 Day ${streakDay}/7 — play tomorrow to keep your streak going!`,
          isRead: false,
          createdAt: admin.firestore.FieldValue.serverTimestamp(),
        });
      }

      console.log(`[applyStreakBonus] ${userId}: Day ${streakDay}/7 streak.`);
    }
  } catch (err) {
    // Non-fatal — scoring still succeeds even if streak update fails
    console.error(`[applyStreakBonus] Error for ${userId}:`, err.message);
  }
}

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

      const { isBestForChallenge, netAurasAwarded } = approved
        ? await applyBestAttemptLogic(submissionId, submission.userId, auraPoints, score, submission.challengeId, challenge.title)
        : { isBestForChallenge: false, netAurasAwarded: 0 };

      const notBestFields = (approved && !isBestForChallenge) ? {
        isArchived: true,
        isPublic: false,
        archiveDeleteAt: admin.firestore.Timestamp.fromDate(new Date(Date.now() + 7 * 24 * 60 * 60 * 1000)),
        archivedReason: 'lower_score',
      } : {};

      await submissionRef.update({
        status: approved ? 'approved' : 'rejected',
        auraPoints,
        netAurasAwarded,
        isBestForChallenge,
        aiScore: score,
        aiReason: reason,
        aiFullResponse: ai,
        reviewedByAI: true,
        usedManualPrompt: true,
        reviewedAt: admin.firestore.FieldValue.serverTimestamp(),
        ...notBestFields,
      });

      if (approved) await applyStreakBonus(submissionId, submission.userId);

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

      const { isBestForChallenge, netAurasAwarded } = approved
        ? await applyBestAttemptLogic(submissionId, submission.userId, auraPoints, score, submission.challengeId, challenge.title)
        : { isBestForChallenge: false, netAurasAwarded: 0 };

      const notBestFields = (approved && !isBestForChallenge) ? {
        isArchived: true,
        isPublic: false,
        archiveDeleteAt: admin.firestore.Timestamp.fromDate(new Date(Date.now() + 7 * 24 * 60 * 60 * 1000)),
        archivedReason: 'lower_score',
      } : {};

      await submissionRef.update({
        status: approved ? 'approved' : 'rejected',
        auraPoints,
        netAurasAwarded,
        isBestForChallenge,
        aiScore: score,
        aiReason: reason,
        reviewedByAI: true,
        usedAiChecklist: true,
        aiChecklistAnswers: checklist.map((q, i) => ({
          question: q,
          answer: answers[i] || 'NO',
        })),
        reviewedAt: admin.firestore.FieldValue.serverTimestamp(),
        ...notBestFields,
      });

      if (approved) await applyStreakBonus(submissionId, submission.userId);

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

      const { isBestForChallenge, netAurasAwarded } = approved
        ? await applyBestAttemptLogic(submissionId, submission.userId, auraPoints, score, submission.challengeId, challenge.title)
        : { isBestForChallenge: false, netAurasAwarded: 0 };

      const notBestFields = (approved && !isBestForChallenge) ? {
        isArchived: true,
        isPublic: false,
        archiveDeleteAt: admin.firestore.Timestamp.fromDate(new Date(Date.now() + 7 * 24 * 60 * 60 * 1000)),
        archivedReason: 'lower_score',
      } : {};

      await submissionRef.update({
        status: approved ? 'approved' : 'rejected',
        auraPoints,
        netAurasAwarded,
        isBestForChallenge,
        aiScore: score,
        aiReason: reason,
        reviewedByAI: true,
        usedAiChecklist: false,
        reviewedAt: admin.firestore.FieldValue.serverTimestamp(),
        ...notBestFields,
      });

      if (approved) await applyStreakBonus(submissionId, submission.userId);
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

// ─────────────────────────────────────────────────────────────────────────────
// SCHEDULED: Runs daily at 2 AM IST. Finds archived submissions whose
// archiveDeleteAt has passed, deletes the video from Storage, and marks
// the Firestore doc as deleted.
// ─────────────────────────────────────────────────────────────────────────────
exports.autoDeleteArchivedSubmissions = onSchedule(
  {
    schedule: '0 2 * * *',
    timeZone: 'Asia/Kolkata',
    memory: '256MiB',
    timeoutSeconds: 540,
  },
  async () => {
    const now = admin.firestore.Timestamp.now();

    const snap = await db.collection('submissions')
      .where('isArchived', '==', true)
      .where('isDeleted', '==', false)
      .where('archiveDeleteAt', '<=', now)
      .get();

    if (snap.empty) {
      console.log('[autoDelete] No submissions to delete today.');
      return;
    }

    console.log(`[autoDelete] Found ${snap.docs.length} submissions to delete.`);

    let deleted = 0;
    let failed = 0;

    for (const doc of snap.docs) {
      const data = doc.data();
      const videoUrl = data.videoUrl || '';

      // Delete video file from Firebase Storage
      if (videoUrl) {
        try {
          const storagePath = _extractStoragePath(videoUrl);
          if (storagePath) {
            await admin.storage().bucket().file(storagePath).delete();
            console.log(`[autoDelete] Deleted storage file: ${storagePath}`);
          }
        } catch (err) {
          // Log but continue — still mark as deleted in Firestore
          console.warn(`[autoDelete] Could not delete storage for ${doc.id}: ${err.message}`);
        }
      }

      // Mark as deleted in Firestore
      try {
        await doc.ref.update({
          isDeleted: true,
          isArchived: false,
          isPublic: false,
          videoUrl: '',
          deletedAt: admin.firestore.FieldValue.serverTimestamp(),
          deletedReason: 'auto_archive_expired',
        });
        deleted++;
      } catch (err) {
        console.error(`[autoDelete] Failed to mark ${doc.id} as deleted: ${err.message}`);
        failed++;
      }
    }

    console.log(`[autoDelete] Done. Deleted: ${deleted}, Failed: ${failed}`);
  }
);

// Extracts the Firebase Storage file path from a download URL.
// e.g. https://firebasestorage.googleapis.com/v0/b/bucket/o/submissions%2Fuid%2Ffile.mp4?alt=media
// → submissions/uid/file.mp4
function _extractStoragePath(videoUrl) {
  try {
    const url = new URL(videoUrl);
    const match = url.pathname.match(/\/o\/(.+)/);
    if (!match) return null;
    return decodeURIComponent(match[1]);
  } catch {
    return null;
  }
}
