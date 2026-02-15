# CloudKit Schema Setup - CRITICAL for Data Sync

⚠️ **IMPORTANT:** CloudKit does **NOT** auto-create schemas. You **MUST** manually upload the schema file or data sync will NOT work.

## Why This Is Required

CloudKit requires explicit schema definitions. The app code serializes data to CloudKit records, but CloudKit will **reject** any fields that aren't defined in the schema. This is a security feature to prevent unauthorized data from being written to your container.

## The Problem with PR #46

PR #46 added code to sync relationship data (doctors, medications, vaccinations, etc.) as JSON strings, but the CloudKit schema was never updated to include these fields. This means:

- ✅ The app code **tries** to write these fields
- ❌ CloudKit **rejects** them because they're not in the schema
- ❌ Data appears to sync but relationships are **silently dropped**

## The Solution

Upload the `cloudkit-development.cdkb` file to CloudKit Dashboard.

## Step-by-Step Instructions

### 1. Access CloudKit Dashboard

1. Go to [CloudKit Dashboard](https://icloud.developer.apple.com/dashboard/)
2. Sign in with your Apple Developer account
3. Select the container: `icloud.com.purus.health`

### 2. Upload Schema to Development Environment

1. Click the **Environment** dropdown at the top
2. Select **Development**
3. Click **Schema** in the left sidebar
4. Click the **Import Schema** button (looks like an upload icon)
5. Select the file: `cloudkit-development.cdkb` from your project root
6. Review the changes - you should see:
   - **New Record Type:** `MedicalRecord`
   - **New Fields:** 41 total fields (see list below)
7. Click **Save Changes**

### 3. Test in Development

1. Build and run your app on a simulator or test device
2. Sign in with a test iCloud account
3. Create a medical record
4. Add some data (medications, doctors, etc.)
5. Enable Cloud Sync on the record
6. Go to CloudKit Dashboard → Data
7. Verify the record exists and contains all fields

### 4. Deploy to Production

⚠️ **Only do this after thorough testing!**

1. In CloudKit Dashboard, select **Development** environment
2. Click **Schema** → **Deploy Schema Changes**
3. Review the changes
4. Click **Deploy to Production**
5. Wait for deployment to complete (can take a few minutes)

## Schema Fields Reference

The `cloudkit-development.cdkb` file defines the following fields:

### Core Fields
- `uuid` (STRING) - Unique identifier
- `createdAt` (TIMESTAMP) - Creation date
- `updatedAt` (TIMESTAMP) - Last update date
- `isPet` (INT64) - Boolean flag (0=human, 1=pet)
- `schemaVersion` (INT64) - Schema version for migrations

### Personal Information (Humans)
- `personalFamilyName` (STRING)
- `personalGivenName` (STRING)
- `personalNickName` (STRING)
- `personalGender` (STRING)
- `personalBirthdate` (TIMESTAMP)
- `personalSocialSecurityNumber` (STRING)
- `personalAddress` (STRING)
- `personalHealthInsurance` (STRING)
- `personalHealthInsuranceNumber` (STRING)
- `personalEmployer` (STRING)

### Pet Information
- `personalName` (STRING) - Pet's name
- `personalAnimalID` (STRING) - Pet ID/microchip
- `ownerName` (STRING)
- `ownerPhone` (STRING)
- `ownerEmail` (STRING)

### Veterinary Information (NEW in PR #46)
- `vetClinicName` (STRING)
- `vetContactName` (STRING)
- `vetPhone` (STRING)
- `vetEmail` (STRING)
- `vetAddress` (STRING)
- `vetNote` (STRING)

### Emergency Contacts (Legacy)
- `emergencyName` (STRING)
- `emergencyNumber` (STRING)
- `emergencyEmail` (STRING)

### Relationship Data as JSON Strings (NEW in PR #46)
These fields store arrays of entries as JSON strings. Each JSON array contains 0-n entries with ALL their data (dates, names, comments, etc.):

- `bloodEntries` (STRING) - JSON array of blood test results: `[{date, name, comment}, ...]`
- `drugEntries` (STRING) - JSON array of medications: `[{date, nameAndDosage, comment}, ...]`
- `vaccinationEntries` (STRING) - JSON array of vaccinations: `[{date, name, information, place, comment}, ...]`
- `allergyEntries` (STRING) - JSON array of allergies: `[{date, name, information, comment}, ...]`
- `illnessEntries` (STRING) - JSON array of illnesses: `[{date, name, informationOrComment}, ...]`
- `riskEntries` (STRING) - JSON array of health risks: `[{date, name, descriptionOrComment}, ...]`
- `medicalHistoryEntries` (STRING) - JSON array of medical history: `[{date, name, contact, informationOrComment}, ...]`
- `medicalDocumentEntries` (STRING) - JSON array of documents: `[{date, name, note}, ...]`
- `humanDoctorEntries` (STRING) - JSON array of doctors: `[{uuid, createdAt, updatedAt, type, name, phone, email, address, note}, ...]`
- `weightEntries` (STRING) - JSON array of weight entries: `[{uuid, createdAt, updatedAt, date, weightKg, comment}, ...]`
- `petYearlyCostEntries` (STRING) - JSON array of pet costs: `[{uuid, createdAt, updatedAt, date, year, category, amount, note}, ...]`
- `emergencyContactEntries` (STRING) - JSON array of emergency contacts: `[{id, name, phone, email, note}, ...]`

**Example:** A `vaccinationEntries` field might contain:
```json
[{"date":1708041600,"name":"COVID-19","information":"Pfizer","place":"Hospital","comment":"No issues"},
 {"date":1710720000,"name":"Flu","information":"Annual","place":"Pharmacy","comment":"OK"}]
```

See `CLOUDKIT-JSON-EXAMPLE.md` for detailed examples of how data is serialized.

## Troubleshooting

### "Schema import failed"
- **Cause:** Syntax error in .cdkb file
- **Solution:** Check the file for typos, missing commas, or invalid types

### "Field type mismatch"
- **Cause:** Trying to change an existing field's type
- **Solution:** CloudKit doesn't allow type changes. You must:
  1. Add a new field with a different name
  2. Migrate data in your app
  3. Remove the old field later

### "Data still not syncing after upload"
- **Solution:**
  1. Verify schema upload in CloudKit Dashboard
  2. Check you're in the correct environment (Development vs Production)
  3. Delete and reinstall the app to clear cache
  4. Check CloudKit Dashboard → Logs for errors

### "Some fields missing in CloudKit"
- **Solution:**
  1. Re-upload the schema file
  2. Ensure all fields are visible in CloudKit Dashboard → Schema
  3. If fields are missing, add them manually:
     - Click **Record Types** → `MedicalRecord`
     - Click **Add Field**
     - Enter field name and select type (STRING for JSON fields)

## Verification Checklist

After uploading the schema, verify:

- [ ] Record type `MedicalRecord` exists
- [ ] All 41 fields are present
- [ ] Field types match (STRING, TIMESTAMP, INT64)
- [ ] Permissions are set: GRANT WRITE TO "_creator", GRANT CREATE TO "_icloud", GRANT READ TO "_world"
- [ ] Schema deployed to Production (after testing)

## Important Notes

1. **CloudKit schemas are permanent** - You can add fields but cannot easily remove them
2. **Type changes are not allowed** - Choose types carefully
3. **Test in Development first** - Always test before deploying to Production
4. **Schema changes are versioned** - CloudKit tracks all changes
5. **Production deployment is one-way** - You cannot easily rollback

## Need Help?

If you're still having sync issues after uploading the schema:

1. Check CloudKit Dashboard → Logs for error messages
2. Look for "field not found" or "unknown field" errors
3. Verify your app is using the correct CloudKit container ID
4. Ensure entitlements are configured correctly in Xcode
5. Check that iCloud is enabled and signed in on your device

---

**Last Updated:** 2026-02-15  
**Related PR:** #46  
**Schema Version:** 1
