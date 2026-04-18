const functions = require('firebase-functions');
const admin = require('firebase-admin');
admin.initializeApp();

// ========== ฟังก์ชันสร้างบุคลากร (ไม่ต้องตรวจสอบ role ใน Firestore) ==========
exports.createPersonnelUser = functions.https.onCall(async (data, context) => {
  // ตรวจสอบว่า user login หรือไม่
  if (!context.auth) {
    throw new functions.https.HttpsError('unauthenticated', 'ต้องเข้าสู่ระบบก่อน');
  }
  
  const callerEmail = context.auth.token.email;
  const callerUid = context.auth.uid;
  
  // ✅ วิธีที่ปลอดภัย: ตรวจสอบว่า caller เป็น admin หรือไม่
  // โดยตรวจสอบจาก email ที่กำหนดไว้ หรือจาก custom claims
  let isAdmin = false;
  
  // 1. ตรวจสอบจาก email ที่กำหนด (แก้ไขตาม email admin ของคุณ)
  const adminEmails = [
    'admin@gmail.com',      // ← แก้เป็น email admin จริง
    'your-email@example.com', // ← แก้เป็น email ที่ใช้ login
  ];
  
  if (adminEmails.includes(callerEmail)) {
    isAdmin = true;
  }
  
  // 2. ตรวจสอบจาก custom claims (ถ้ามี)
  if (context.auth.token.admin === true) {
    isAdmin = true;
  }
  
  // 3. ถ้ายังไม่มี admin ในระบบ ให้คนแรกเป็น admin อัตโนมัติ
  if (!isAdmin) {
    const adminQuery = await admin.firestore()
      .collection('user_personal')
      .where('role', '==', 'admin')
      .limit(1)
      .get();
    
    if (adminQuery.empty) {
      isAdmin = true;
      // อัพเดท user ปัจจุบันเป็น admin
      await admin.firestore().collection('user_personal').doc(callerUid).set({
        role: 'admin',
        email: callerEmail,
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      }, { merge: true });
      
      // ตั้ง custom claims
      await admin.auth().setCustomUserClaims(callerUid, { admin: true, role: 'admin' });
    }
  }
  
  if (!isAdmin) {
    throw new functions.https.HttpsError('permission-denied', 'เฉพาะ Admin เท่านั้นที่สามารถสร้างบุคลากร');
  }
  
  const { 
    email, 
    password, 
    firstName, 
    lastName, 
    educationLevel, 
    year, 
    year_base, 
    room, 
    department, 
    createdBy, 
    createdByEmail 
  } = data;
  
  // ตรวจสอบข้อมูลจำเป็น
  if (!email || !password || !firstName || !lastName) {
    throw new functions.https.HttpsError('invalid-argument', 'กรุณากรอกข้อมูลให้ครบถ้วน');
  }
  
  try {
    // 1. สร้าง user ใน Authentication
    const userRecord = await admin.auth().createUser({
      email: email,
      password: password,
      displayName: `$firstName $lastName`,
    });
    
    // 2. ตั้งค่า custom claims
    await admin.auth().setCustomUserClaims(userRecord.uid, {
      role: 'personnel'
    });
    
    // 3. บันทึกข้อมูลลง Firestore
    await admin.firestore().collection('user_personal').doc(userRecord.uid).set({
      userId: userRecord.uid,
      email: email,
      firstName: firstName,
      lastName: lastName,
      educationLevel: educationLevel,
      year: year,
      year_base: year_base,
      room: room,
      department: department,
      role: 'personnel',
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      createdBy: createdBy,
      createdByEmail: createdByEmail,
    });
    
    console.log(`✅ Created personnel user: ${userRecord.uid}`);
    
    return {
      success: true,
      uid: userRecord.uid,
      message: 'สร้างบุคลากรสำเร็จ'
    };
    
  } catch (error) {
    console.error('❌ Error creating personnel:', error);
    throw new functions.https.HttpsError('internal', `ไม่สามารถสร้างบุคลากร: ${error.message}`);
  }
});

// ========== ฟังก์ชันสร้างนักเรียน (student) - ใหม่ ไม่กระทบของเดิม ==========
exports.createStudentUser = functions.https.onCall(async (data, context) => {
  // ตรวจสอบว่า user login หรือไม่
  if (!context.auth) {
    throw new functions.https.HttpsError('unauthenticated', 'ต้องเข้าสู่ระบบก่อน');
  }
  
  const callerEmail = context.auth.token.email;
  const callerUid = context.auth.uid;
  
  // ✅ ตรวจสอบว่า caller เป็น admin หรือไม่ (ใช้ logic เดียวกับ createPersonnelUser)
  let isAdmin = false;
  
  // 1. ตรวจสอบจาก email ที่กำหนด
  const adminEmails = [
    'admin@gmail.com',      // ← แก้เป็น email admin จริง
    'your-email@example.com', // ← แก้เป็น email ที่ใช้ login
  ];
  
  if (adminEmails.includes(callerEmail)) {
    isAdmin = true;
  }
  
  // 2. ตรวจสอบจาก custom claims
  if (context.auth.token.admin === true) {
    isAdmin = true;
  }
  
  // 3. ตรวจสอบจาก Firestore (user_personal สำหรับ personnel)
  if (!isAdmin) {
    const callerSnapshot = await admin.firestore().collection('user_personal').doc(callerUid).get();
    const callerData = callerSnapshot.data();
    if (callerData && callerData.role === 'admin') {
      isAdmin = true;
    }
  }
  
  // 4. ตรวจสอบจาก Firestore (users สำหรับ student - เผื่อ admin อยู่ใน users)
  if (!isAdmin) {
    const callerSnapshot = await admin.firestore().collection('users').doc(callerUid).get();
    const callerData = callerSnapshot.data();
    if (callerData && callerData.role === 'admin') {
      isAdmin = true;
    }
  }
  
  if (!isAdmin) {
    throw new functions.https.HttpsError('permission-denied', 'เฉพาะ Admin เท่านั้นที่สามารถสร้างนักเรียน');
  }
  
  const { 
    email, 
    password, 
    firstName, 
    lastName, 
    title, 
    studentId, 
    department, 
    educationLevel, 
    year, 
    createdBy, 
    createdByEmail 
  } = data;
  
  // ตรวจสอบข้อมูลจำเป็น
  if (!email || !password || !firstName || !lastName || !studentId) {
    throw new functions.https.HttpsError('invalid-argument', 'กรุณากรอกข้อมูลให้ครบถ้วน');
  }
  
  try {
    // 1. ตรวจสอบว่ามี email ซ้ำใน Authentication หรือไม่
    try {
      const existingUser = await admin.auth().getUserByEmail(email);
      if (existingUser) {
        throw new functions.https.HttpsError('already-exists', 'อีเมลนี้มีผู้ใช้แล้ว');
      }
    } catch (e) {
      if (e.code === 'auth/user-not-found') {
        // ไม่มีผู้ใช้ ดีต่อ
      } else {
        throw e;
      }
    }
    
    // 2. สร้าง user ใน Authentication
    const userRecord = await admin.auth().createUser({
      email: email,
      password: password,
      displayName: `$firstName $lastName`,
    });
    
    // 3. ตั้งค่า custom claims
    await admin.auth().setCustomUserClaims(userRecord.uid, {
      role: 'student'
    });
    
    // 4. บันทึกข้อมูลลง Firestore (collection users)
    await admin.firestore().collection('users').doc(userRecord.uid).set({
      userId: userRecord.uid,
      email: email,
      firstName: firstName,
      lastName: lastName,
      title: title || '',
      role: 'student',
      studentId: studentId,
      department: department || '',
      educationLevel: educationLevel || 'ปวช',
      year: year || '',
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      createdBy: createdBy,
      createdByEmail: createdByEmail,
    });
    
    console.log(`✅ Created student user: ${userRecord.uid} (${email})`);
    
    return {
      success: true,
      uid: userRecord.uid,
      message: 'สร้างนักเรียนสำเร็จ'
    };
    
  } catch (error) {
    console.error('❌ Error creating student:', error);
    throw new functions.https.HttpsError('internal', `ไม่สามารถสร้างนักเรียน: ${error.message}`);
  }
});

// ========== ฟังก์ชันลบ user (รองรับทั้ง user_personal และ users) ==========
exports.deleteUser = functions.https.onCall(async (data, context) => {
  if (!context.auth) {
    throw new functions.https.HttpsError('unauthenticated', 'ต้องเข้าสู่ระบบก่อน');
  }
  
  const callerUid = context.auth.uid;
  
  // ✅ ตรวจสอบว่า caller เป็น admin หรือไม่ (ตรวจสอบหลายที่)
  let isAdmin = false;
  
  // ตรวจสอบจาก user_personal
  try {
    const callerSnapshot = await admin.firestore().collection('user_personal').doc(callerUid).get();
    const callerData = callerSnapshot.data();
    if (callerData && callerData.role === 'admin') {
      isAdmin = true;
    }
  } catch (e) {
    console.log('ไม่พบใน user_personal:', e);
  }
  
  // ตรวจสอบจาก users (เผื่อ admin อยู่ใน users)
  if (!isAdmin) {
    try {
      const callerSnapshot = await admin.firestore().collection('users').doc(callerUid).get();
      const callerData = callerSnapshot.data();
      if (callerData && callerData.role === 'admin') {
        isAdmin = true;
      }
    } catch (e) {
      console.log('ไม่พบใน users:', e);
    }
  }
  
  if (!isAdmin) {
    throw new functions.https.HttpsError('permission-denied', 'เฉพาะ Admin เท่านั้นที่สามารถลบผู้ใช้');
  }
  
  const uid = data.uid;
  
  if (!uid) {
    throw new functions.https.HttpsError('invalid-argument', 'ต้องระบุ uid');
  }
  
  try {
    // ลบ user จาก Authentication
    await admin.auth().deleteUser(uid);
    console.log(`✅ Deleted user: ${uid}`);
    
    // ลบข้อมูลจาก Firestore ทั้งสอง collection (เผื่อมีข้อมูลตกค้าง)
    try {
      await admin.firestore().collection('user_personal').doc(uid).delete();
    } catch (e) {
      console.log('ไม่มีข้อมูลใน user_personal หรือลบไปแล้ว');
    }
    
    try {
      await admin.firestore().collection('users').doc(uid).delete();
    } catch (e) {
      console.log('ไม่มีข้อมูลใน users หรือลบไปแล้ว');
    }
    
    return { success: true, message: 'ลบผู้ใช้สำเร็จ' };
  } catch (error) {
    console.error(`❌ Error deleting user ${uid}:`, error);
    throw new functions.https.HttpsError('internal', error.message);
  }
});
