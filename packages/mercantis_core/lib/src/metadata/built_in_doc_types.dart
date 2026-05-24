import 'doc_type.dart';
import 'field_definition.dart';
import 'permission_rule.dart';
import 'metadata_registry.dart';

class BuiltInDocTypes {
  static Future<void> register(MetadataRegistry registry) async {
    await registry.register(_moduleDocType);
    await registry.register(_roleDocType);
    await registry.register(_userDocType);
    await registry.register(_companyDocType);
    await registry.register(_fileDocType);
    await registry.register(_notificationLogDocType);
    await registry.register(_workflowDefinitionDocType);
    await registry.register(_customFieldDocType);
    await registry.register(_propertySetterDocType);
    await registry.register(_docTypeDocType);
  }

  static const _adminPermission = [
    PermissionRule(
      role: 'System Manager',
      read: true, write: true, create: true, delete: true, submit: false, amend: false,
    ),
  ];

  static const _moduleDocType = DocType(
    id: 'Module',
    name: 'Module',
    fields: [
      FieldDefinition(key: 'module_name', type: FieldType.data, label: 'Module Name', required: true, unique: true),
      FieldDefinition(key: 'app_name', type: FieldType.data, label: 'App Name'),
      FieldDefinition(key: 'description', type: FieldType.text, label: 'Description'),
    ],
    permissions: _adminPermission,
  );

  static const _roleDocType = DocType(
    id: 'Role',
    name: 'Role',
    fields: [
      FieldDefinition(key: 'role_name', type: FieldType.data, label: 'Role Name', required: true, unique: true),
      FieldDefinition(key: 'is_custom', type: FieldType.check, label: 'Is Custom'),
      FieldDefinition(key: 'desk_access', type: FieldType.check, label: 'Desk Access'),
      FieldDefinition(key: 'description', type: FieldType.text, label: 'Description'),
    ],
    permissions: _adminPermission,
  );

  static const _userDocType = DocType(
    id: 'User',
    name: 'User',
    isSingleton: false,
    fields: [
      FieldDefinition(key: 'email', type: FieldType.data, label: 'Email', required: true, unique: true),
      FieldDefinition(key: 'full_name', type: FieldType.data, label: 'Full Name', required: true),
      FieldDefinition(key: 'username', type: FieldType.data, label: 'Username'),
      FieldDefinition(key: 'enabled', type: FieldType.check, label: 'Enabled', defaultValue: '1'),
      FieldDefinition(key: 'language', type: FieldType.data, label: 'Language'),
      FieldDefinition(key: 'time_zone', type: FieldType.data, label: 'Time Zone'),
      FieldDefinition(key: 'roles', type: FieldType.table, label: 'Roles', tableDocType: 'UserRole'),
    ],
    permissions: _adminPermission,
  );

  static const _companyDocType = DocType(
    id: 'Company',
    name: 'Company',
    fields: [
      FieldDefinition(key: 'company_name', type: FieldType.data, label: 'Company Name', required: true, unique: true),
      FieldDefinition(key: 'abbr', type: FieldType.data, label: 'Abbreviation', required: true),
      FieldDefinition(key: 'default_currency', type: FieldType.link, label: 'Default Currency', linkDocType: 'Currency'),
      FieldDefinition(key: 'country', type: FieldType.data, label: 'Country'),
      FieldDefinition(key: 'phone_no', type: FieldType.data, label: 'Phone No'),
      FieldDefinition(key: 'address', type: FieldType.text, label: 'Address'),
    ],
    permissions: _adminPermission,
  );

  static const _fileDocType = DocType(
    id: 'File',
    name: 'File',
    fields: [
      FieldDefinition(key: 'file_name', type: FieldType.data, label: 'File Name', required: true),
      FieldDefinition(key: 'file_url', type: FieldType.data, label: 'File URL'),
      FieldDefinition(key: 'file_size', type: FieldType.integer, label: 'File Size'),
      FieldDefinition(key: 'mime_type', type: FieldType.data, label: 'MIME Type'),
      FieldDefinition(key: 'is_private', type: FieldType.check, label: 'Is Private'),
      FieldDefinition(key: 'attached_to_doctype', type: FieldType.data, label: 'Attached To DocType'),
      FieldDefinition(key: 'attached_to_name', type: FieldType.data, label: 'Attached To Name'),
      FieldDefinition(key: 'attached_to_field', type: FieldType.data, label: 'Attached To Field'),
    ],
    permissions: _adminPermission,
  );

  static const _notificationLogDocType = DocType(
    id: 'Notification Log',
    name: 'Notification Log',
    fields: [
      FieldDefinition(key: 'subject', type: FieldType.data, label: 'Subject', required: true),
      FieldDefinition(key: 'email_content', type: FieldType.text, label: 'Content'),
      FieldDefinition(key: 'document_type', type: FieldType.data, label: 'Document Type'),
      FieldDefinition(key: 'document_name', type: FieldType.data, label: 'Document Name'),
      FieldDefinition(key: 'for_user', type: FieldType.link, label: 'For User', linkDocType: 'User'),
      FieldDefinition(key: 'type', type: FieldType.select, label: 'Type', options: 'Alert\nMention\nAssignment\nShare\nEnergy Point'),
      FieldDefinition(key: 'read', type: FieldType.check, label: 'Read'),
    ],
    permissions: _adminPermission,
  );

  static const _workflowDefinitionDocType = DocType(
    id: 'Workflow',
    name: 'Workflow',
    fields: [
      FieldDefinition(key: 'workflow_name', type: FieldType.data, label: 'Workflow Name', required: true),
      FieldDefinition(key: 'document_type', type: FieldType.link, label: 'Document Type', linkDocType: 'DocType'),
      FieldDefinition(key: 'is_active', type: FieldType.check, label: 'Is Active'),
      FieldDefinition(key: 'states', type: FieldType.table, label: 'States', tableDocType: 'WorkflowState'),
      FieldDefinition(key: 'transitions', type: FieldType.table, label: 'Transitions', tableDocType: 'WorkflowTransition'),
    ],
    permissions: _adminPermission,
  );

  static const _customFieldDocType = DocType(
    id: 'Custom Field',
    name: 'Custom Field',
    fields: [
      FieldDefinition(key: 'dt', type: FieldType.link, label: 'DocType', linkDocType: 'DocType', required: true),
      FieldDefinition(key: 'fieldname', type: FieldType.data, label: 'Field Name', required: true),
      FieldDefinition(key: 'fieldtype', type: FieldType.select, label: 'Field Type', required: true),
      FieldDefinition(key: 'label', type: FieldType.data, label: 'Label'),
      FieldDefinition(key: 'insert_after', type: FieldType.data, label: 'Insert After'),
      FieldDefinition(key: 'reqd', type: FieldType.check, label: 'Mandatory'),
    ],
    permissions: _adminPermission,
  );

  static const _propertySetterDocType = DocType(
    id: 'Property Setter',
    name: 'Property Setter',
    fields: [
      FieldDefinition(key: 'doc_type', type: FieldType.link, label: 'DocType', linkDocType: 'DocType', required: true),
      FieldDefinition(key: 'field_name', type: FieldType.data, label: 'Field Name', required: true),
      FieldDefinition(key: 'property', type: FieldType.data, label: 'Property', required: true),
      FieldDefinition(key: 'value', type: FieldType.data, label: 'Value'),
    ],
    permissions: _adminPermission,
  );

  static const _docTypeDocType = DocType(
    id: 'DocType',
    name: 'DocType',
    fields: [
      FieldDefinition(key: 'name', type: FieldType.data, label: 'Name', required: true, unique: true),
      FieldDefinition(key: 'module', type: FieldType.link, label: 'Module', linkDocType: 'Module'),
      FieldDefinition(key: 'is_submittable', type: FieldType.check, label: 'Is Submittable'),
      FieldDefinition(key: 'is_singleton', type: FieldType.check, label: 'Is Singleton'),
      FieldDefinition(key: 'is_child_table', type: FieldType.check, label: 'Is Child Table'),
      FieldDefinition(key: 'fields', type: FieldType.table, label: 'Fields', tableDocType: 'DocType Field'),
      FieldDefinition(key: 'permissions', type: FieldType.table, label: 'Permissions', tableDocType: 'DocType Permission'),
    ],
    permissions: _adminPermission,
  );
}
