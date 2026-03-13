const functions = require('firebase-functions');
const admin = require('firebase-admin');
admin.initializeApp();

exports.deleteUser = functions.https.onCall(async (data, context) => {
  // ตรวจสอบว่า user login หรือไม่
  if (!context.auth) {
    throw new functions.https.HttpsError(
      'unauthenticated',
      'ต้องเข้าสู่ระบบก่อน'
    );
  }
  
  // ตรวจสอบว่า user ที่เรียกเป็น Admin
  const callerUid = context.auth.uid;
  const callerSnapshot = await admin.firestore().collection('users').doc(callerUid).get();
  const callerData = callerSnapshot.data();
  
  if (!callerData || callerData.role !== 'admin') {
    throw new functions.https.HttpsError(
      'permission-denied',
      'เฉพาะ Admin เท่านั้นที่สามารถลบผู้ใช้'
    );
  }
  
  const uid = data.uid;
  
  if (!uid) {
    throw new functions.https.HttpsError(
      'invalid-argument',
      'ต้องระบุ uid'
    );
  }
  
  try {
    // ลบ user จาก Authentication
    await admin.auth().deleteUser(uid);
    console.log(`✅ Deleted user: ${uid}`);
    return { success: true, message: 'ลบผู้ใช้สำเร็จ' };
  } catch (error) {
    console.error(`❌ Error deleting user ${uid}:`, error);
    throw new functions.https.HttpsError('internal', error.message);
  }
});