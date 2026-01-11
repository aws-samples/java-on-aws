import boto3
import json

codebuild = boto3.client('codebuild')

def lambda_handler(event, context):
    print(f'Build status event: {event}')

    try:
        # Extract build information from EventBridge event
        detail = event['detail']
        build_status = detail['build-status']
        project_name = detail['project-name']
        build_id = detail['build-id']

        print(f'Build {build_id} for project {project_name} finished with status: {build_status}')

        if build_status == 'SUCCEEDED':
            print('✅ CodeBuild setup completed successfully')
        elif build_status == 'FAILED':
            print('❌ CodeBuild setup failed')

            # Get build details for error information
            response = codebuild.batch_get_builds(ids=[build_id])
            if response['builds']:
                build = response['builds'][0]
                if 'logs' in build and 'cloudWatchLogs' in build['logs']:
                    log_group = build['logs']['cloudWatchLogs'].get('groupName')
                    log_stream = build['logs']['cloudWatchLogs'].get('streamName')
                    print(f'Check logs at: {log_group}/{log_stream}')
        elif build_status == 'STOPPED':
            print('⏹️ CodeBuild setup was stopped')

        return {
            'statusCode': 200,
            'body': json.dumps({
                'message': f'Processed build status: {build_status}',
                'buildId': build_id,
                'projectName': project_name
            })
        }

    except Exception as e:
        print(f'Error processing build status: {str(e)}')
        return {
            'statusCode': 500,
            'body': json.dumps({
                'error': str(e)
            })
        }