Aws.config.update(stub_responses: true)

module FakeS3
  def fake_s3(objects = {})
    Aws::S3::Client.new(stub_responses: true).tap do |client|
      client.stub_responses(:put_object, lambda { |context|
        body = context.params[:body]
        body.rewind
        objects[context.params[:key]] = { body: body.read, metadata: context.params[:metadata] }
        {}
      })
      client.stub_responses(:head_object, lambda { |context|
        object = objects.fetch(context.params[:key])
        { content_length: object[:body].bytesize, metadata: object[:metadata] }
      })
    end
  end
end

RSpec.configure { |config| config.include(FakeS3) }
