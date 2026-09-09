/**
 * One-time script: generate YES/NO scoring checklists for all existing challenges.
 *
 * Usage:
 *   cd functions
 *   GEMINI_API_KEY=your_key SERVICE_ACCOUNT=../serviceAccount.json node backfill_rubrics.js
 *   GEMINI_API_KEY=your_key SERVICE_ACCOUNT=../serviceAccount.json node backfill_rubrics.js --force
 */

const { GoogleGenerativeAI } = require('@google/generative-ai');
const { GoogleAIFileManager } = require('@google/generative-ai/server');
const admin = require('firebase-admin');
const fs = require('fs');
const os = require('os');
const path = require('path');

const GEMINI_API_KEY = process.env.GEMINI_API_KEY;
if (!GEMINI_API_KEY) {
  console.error('ERROR: Set GEMINI_API_KEY before running.');
  process.exit(1);
}

const serviceAccountPath = process.env.SERVICE_ACCOUNT;
if (!serviceAccountPath || !fs.existsSync(serviceAccountPath)) {
  console.error('ERROR: Set SERVICE_ACCOUNT to the path of your Firebase service account JSON.');
  process.exit(1);
}

admin.initializeApp({
  credential: admin.credential.cert(JSON.parse(fs.readFileSync(serviceAccountPath, 'utf8'))),
  projectId: 'aura-app-efae1',
});
const db = admin.firestore();

async function downloadToTemp(url, filename) {
  const response = await fetch(url);
  if (!response.ok) throw new Error(`Download failed (${response.status}): ${url}`);
  const buffer = Buffer.from(await response.arrayBuffer());
  const tempPath = path.join(os.tmpdir(), filename);
  fs.writeFileSync(tempPath, buffer);
  return tempPath;
}

async function uploadVideoToGemini(fileManager, filePath, displayName) {
  const result = await fileManager.uploadFile(filePath, { mimeType: 'video/mp4', displayName });
  let file = result.file;
  while (file.state === 'PROCESSING') {
    await new Promise(r => setTimeout(r, 3000));
    file = await fileManager.getFile(file.name);
  }
  if (file.state === 'FAILED') throw new Error(`Gemini processing failed for: ${displayName}`);
  return file;
}

async function generateChecklistForChallenge(challenge, challengeId) {
  const fileManager = new GoogleAIFileManager(GEMINI_API_KEY);
  const uploadedFileNames = [];
  const tempFiles = [];

  try {
    console.log(`  Downloading reference video...`);
    const refTempPath = await downloadToTemp(challenge.videoUrl, `rubric_ref_${challengeId}.mp4`);
    tempFiles.push(refTempPath);

    console.log(`  Uploading to Gemini...`);
    const refFile = await uploadVideoToGemini(fileManager, refTempPath, 'reference_video');
    uploadedFileNames.push(refFile.name);

    const genAI = new GoogleGenerativeAI(GEMINI_API_KEY);
    const model = genAI.getGenerativeModel({ model: 'gemini-2.5-flash' });

    console.log(`  Generating YES/NO checklist...`);
    const result = await model.generateContent({
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

    const checklist = JSON.parse(result.response.text().trim());

    if (!Array.isArray(checklist) || checklist.length === 0) {
      throw new Error('Gemini did not return a valid checklist array.');
    }

    console.log(`  Saving ${checklist.length} questions to Firestore...`);
    await db.collection('challenges').doc(challengeId).update({
      aiScoringChecklist: checklist,
      aiRubricGeneratedAt: admin.firestore.FieldValue.serverTimestamp(),
    });

    console.log(`  ✓ Done.\n`);
    return true;

  } catch (err) {
    console.error(`  ✗ Failed: ${err.message}\n`);
    return false;
  } finally {
    for (const p of tempFiles) { try { fs.unlinkSync(p); } catch (_) {} }
    for (const name of uploadedFileNames) { try { await fileManager.deleteFile(name); } catch (_) {} }
  }
}

async function main() {
  const force = process.argv.includes('--force');
  if (force) console.log('--force mode: regenerating ALL checklists.\n');

  console.log('Fetching challenges from Firestore...\n');
  const snapshot = await db.collection('challenges').get();
  const toProcess = [];

  for (const doc of snapshot.docs) {
    const data = doc.data();
    if (data.videoUrl && (!data.aiScoringChecklist || force)) {
      toProcess.push({ id: doc.id, data });
    }
  }

  if (toProcess.length === 0) {
    console.log('No challenges need a checklist — all are already up to date.');
    console.log('Run with --force to regenerate all checklists.');
    process.exit(0);
  }

  console.log(`Found ${toProcess.length} challenge(s) to process:\n`);
  toProcess.forEach((c, i) => console.log(`  ${i + 1}. [${c.id}] ${c.data.title}`));
  console.log('');

  let success = 0;
  let failure = 0;

  for (const { id, data } of toProcess) {
    console.log(`Processing: "${data.title}" (${id})`);
    const ok = await generateChecklistForChallenge(data, id);
    if (ok) success++; else failure++;
    await new Promise(r => setTimeout(r, 2000));
  }

  console.log('─────────────────────────────');
  console.log(`Done. ${success} succeeded, ${failure} failed.`);
  process.exit(failure > 0 ? 1 : 0);
}

main().catch(err => {
  console.error('Unexpected error:', err);
  process.exit(1);
});
