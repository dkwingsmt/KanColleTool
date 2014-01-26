//
//  KVHTTPProtocol.m
//  KCTViewer
//
//  Created by Johannes Ekberg on 2014-01-15.
//  Copyright (c) 2014 MacaroniCode. All rights reserved.
//

#import "KVHTTPProtocol.h"
#import "KVTranslator.h"

@implementation KVHTTPProtocol

+ (BOOL)canInitWithRequest:(NSURLRequest *)request
{
	return [request.URL.scheme isEqualToString:@"http"] && [request.HTTPMethod isEqualToString:@"POST"] && ![[self class] propertyForKey:@"_handled" inRequest:request];
}

+ (NSURLRequest *)canonicalRequestForRequest:(NSURLRequest *)request
{
	return request;
}

- (id)initWithRequest:(NSURLRequest *)request cachedResponse:(NSCachedURLResponse *)cachedResponse client:(id<NSURLProtocolClient>)client
{
	return [super initWithRequest:[request mutableCopy] cachedResponse:cachedResponse client:client];
}

- (void)startLoading
{
	[[self class] setProperty:[NSNumber numberWithBool:YES] forKey:@"_handled" inRequest:(NSMutableURLRequest*)self.request];
	self.interesting = [self.request.URL.path hasPrefix:@"/kcsapi"];
	self.connection = [NSURLConnection connectionWithRequest:self.request delegate:self];
}

- (void)stopLoading
{
	[self.connection cancel];
}

- (void)connection:(NSURLConnection *)connection didReceiveData:(NSData *)data
{
	if(!self.interesting)
		[self.client URLProtocol:self didLoadData:data];
	else
		if(!self.buffer) self.buffer = [[NSMutableData alloc] initWithData:data];
		else [self.buffer appendData:data];
}

- (void)connection:(NSURLConnection *)connection didFailWithError:(NSError *)error
{
	[self.client URLProtocol:self didFailWithError:error];
	self.connection = nil;
}

- (void)connection:(NSURLConnection *)connection didReceiveResponse:(NSURLResponse *)response
{
	// In the case of multipart requests, this may be called several times, in which case the
	// docs say we should empty the buffer before delivering the new response.
	if([self.buffer length] > 0)
		[self deliverResponse];
	
	/*for(NSString *key in [(NSHTTPURLResponse*)response allHeaderFields])
		NSLog(@"%@ : %@", key, [[(NSHTTPURLResponse*)response allHeaderFields] objectForKey:key]);*/
	[self.client URLProtocol:self didReceiveResponse:response
		  cacheStoragePolicy:([self.request.URL.path hasPrefix:@"/kcsapi"] ? NSURLCacheStorageNotAllowed : NSURLCacheStorageAllowed)];
}

- (void)connectionDidFinishLoading:(NSURLConnection *)connection
{
	// Deliver buffered data
	[self deliverResponse];
	
	// Tell the client the request is finished
	[self.client URLProtocolDidFinishLoading:self];
	self.connection = nil;
}

- (void)deliverResponse
{
	if(self.buffer)
	{
		// This should always be true (we shouldn't have a buffer if the request is not interesting,
		// but it's always good to check a second time. That might change in the future or something.
		if([self isInteresting])
		{
			NSData *translatedData = [[KVTranslator sharedTranslator] translateJSON:self.buffer];
			[self.client URLProtocol:self didLoadData:translatedData];
		}
		// If this request is uninteresting, just feed the client the buffer, and wonder why
		// the heck we buffered the response in the first place.
		else
			[self.client URLProtocol:self didLoadData:self.buffer];
		
		// Because properties' magical reference counting, this also releases the buffer
		self.buffer = nil;
	}
}

@end