// Metadata
export 'src/metadata/doc_type.dart';
export 'src/metadata/document_naming_rule.dart';
export 'src/metadata/field_definition.dart';
export 'src/metadata/permission_rule.dart';
export 'src/metadata/sync_policy.dart';
export 'src/metadata/index_definition.dart';
export 'src/metadata/resolved_meta.dart';
export 'src/metadata/metadata_registry.dart';
export 'src/metadata/meta_composer.dart';
export 'src/metadata/schema_validator.dart';
export 'src/metadata/built_in_doc_types.dart';

// Document Engine
export 'src/document_engine/document.dart';
export 'src/document_engine/document_engine.dart';
export 'src/document_engine/document_version.dart';
export 'src/document_engine/list_filter.dart';
export 'src/document_engine/validation_pipeline.dart';

// Storage
export 'src/storage/mercantis_database.dart';
export 'src/storage/migration_runner.dart';

// Permissions
export 'src/permissions/permission_engine.dart';

// Workflow
export 'src/workflow/workflow_engine.dart';
export 'src/workflow/workflow_transition_history.dart';

// Expression Engine
export 'src/expression_engine/expression_ast.dart';
export 'src/expression_engine/expression_parser.dart';
export 'src/expression_engine/expression_evaluator.dart';
export 'src/expression_engine/document_lookup_resolver.dart';

// Sync Engine
export 'src/sync_engine/mutation_record.dart';
export 'src/sync_engine/cloud_adapter.dart';
export 'src/sync_engine/conflict_resolver.dart';
export 'src/sync_engine/sync_engine.dart';

// Naming
export 'src/naming/naming_strategy.dart';
export 'src/naming/naming_service.dart';
export 'src/naming/counter_block_allocator.dart';

// Automation
export 'src/automation/automation_action_handler.dart';
export 'src/automation/automation_action_registry.dart';
export 'src/automation/built_in_action_handlers.dart';
export 'src/automation/automation_runner.dart';

// App Runtime
export 'src/app_runtime/app_manifest.dart';
export 'src/app_runtime/app_installer.dart';
export 'src/app_runtime/extension_point_resolver.dart';

// Notifications / Events
export 'src/notifications/event_emitter.dart';
export 'src/notifications/notification_log.dart';
export 'src/notifications/notification_inbox.dart';

// Scheduling
export 'src/scheduling/scheduled_task.dart';
export 'src/scheduling/cron_expression.dart';
export 'src/scheduling/scheduler_service.dart';

// Customization
export 'src/customization/custom_field.dart';
export 'src/customization/property_setter.dart';

// Reporting / Dashboards
export 'src/reporting/report_value_formatter.dart';
export 'src/reporting/report_result.dart';
export 'src/reporting/report_engine.dart';
export 'src/reporting/dashboard_result.dart';
export 'src/reporting/dashboard_engine.dart';
export 'src/reporting/saved_report_definition.dart';
export 'src/reporting/saved_report_engine.dart';
export 'src/import_export/import_export_format.dart';
export 'src/import_export/csv_codec.dart';
export 'src/import_export/data_exporter.dart';
export 'src/import_export/data_importer.dart';
export 'src/files/attachment.dart';
export 'src/files/attachment_store.dart';
export 'src/files/attachment_manager.dart';
export 'src/printing/print_format.dart';
export 'src/printing/print_renderer.dart';
export 'src/printing/plain_text_print_renderer.dart';
export 'src/printing/pdf_print_renderer.dart';
export 'src/printing/print_service.dart';
